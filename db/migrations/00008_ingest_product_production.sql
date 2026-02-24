-- +goose Up
-- +goose StatementBegin

CREATE OR REPLACE FUNCTION dirac.ingest_product(
  p_barcode text,
  p_name text,
  p_description text DEFAULT NULL
)
RETURNS dirac.product
LANGUAGE plpgsql
AS $$
DECLARE
  v_ean13 dirac.ean13;
  v_product_id bigint;
  v_row dirac.product;
  v_row_existing dirac.product;
  v_cleaned text;
BEGIN
  /* Basic validation where the product has to have a name */
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'name must be non-empty'
      USING ERRCODE = '22023';
  END IF;

  /* Protocol : missing barcode => create product + flag */
  IF p_barcode IS NULL OR btrim(p_barcode) = '' THEN
    INSERT INTO dirac.product (name, description)
    VALUES (p_name, p_description)
    RETURNING * INTO v_row;

    INSERT INTO dirac.flagged_barcode(raw_barcode, cleaned_barcode, reason)
    VALUES (COALESCE(p_barcode, ''), NULL, 'missing barcode');

    RETURN v_row;
  END IF;

  /* Trim, remove whitespaces + hyphens only (do NOT silently drop other characters) */
  v_cleaned := regexp_replace(btrim(p_barcode), '[\s-]+', '', 'g');

  BEGIN
    /* normalise to EAN-13 format (UPC-A -> leading 0). */
    v_ean13 := dirac.normalize_to_ean13(p_barcode);

    /* Serialize per canonical barcode to prevent duplicates under concurrency */
    PERFORM pg_advisory_xact_lock(hashtextextended(v_ean13::text, 0));

    /* If barcode already mapped, update existing product and return it */
    SELECT pb.product_id
      INTO v_product_id
    FROM dirac.product_barcode pb
    WHERE pb.barcode = v_ean13;

    IF v_product_id IS NOT NULL THEN
      UPDATE dirac.product p
      SET name = p_name,
          description = COALESCE(p_description, p.description)
      WHERE p.id = v_product_id
      RETURNING * INTO v_row;

      RETURN v_row;
    END IF;

    /* Otherwise create a new product and attach mapping */
    INSERT INTO dirac.product (name, description)
    VALUES (p_name, p_description)
    RETURNING * INTO v_row;

    BEGIN
      INSERT INTO dirac.product_barcode (barcode, product_id)
      VALUES (v_ean13, v_row.id);

      RETURN v_row;

    EXCEPTION
      WHEN unique_violation THEN
        /*
          Another concurrent transaction inserted the barcode mapping first (or a lock collision occurred).
          Resolve by returning/updating the existing mapped product, and delete the "loser" product row
          we just created to avoid leaving an orphan.
        */
        SELECT pb.product_id
          INTO v_product_id
        FROM dirac.product_barcode pb
        WHERE pb.barcode = v_ean13;

        IF v_product_id IS NULL THEN
          RAISE; -- unexpected: unique_violation but no row found
        END IF;

        UPDATE dirac.product p
        SET name = p_name,
            description = COALESCE(p_description, p.description)
        WHERE p.id = v_product_id
        RETURNING * INTO v_row_existing;

        IF v_row.id <> v_product_id THEN
          DELETE FROM dirac.product
          WHERE id = v_row.id;
        END IF;

        RETURN v_row_existing;
    END;

  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      /* Protocol : if Normalization failed (invalid/unsupported format) create product + add to flagged_barcode table, return product */
      INSERT INTO dirac.product (name, description)
      VALUES (p_name, p_description)
      RETURNING * INTO v_row;

      INSERT INTO dirac.flagged_barcode(raw_barcode, cleaned_barcode, reason)
      VALUES (p_barcode, v_cleaned, SQLERRM);

      RETURN v_row;
  END;
END;
$$;

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP FUNCTION IF EXISTS dirac.ingest_product(text, text, text);
-- +goose StatementEnd