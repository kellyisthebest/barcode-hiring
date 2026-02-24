-- +goose Up
-- +goose StatementBegin

/* this is a new version of the ingest_product function that adds handling for concurrent transactions trying to insert the same barcode.
 It uses a "try to insert, if fails then update existing" pattern. */

CREATE OR REPLACE FUNCTION dirac.ingest_product(
  p_barcode text,
  p_name text,
  p_description text DEFAULT NULL
)
RETURNS dirac.product
LANGUAGE plpgsql
AS $$
DECLARE
  v_barcode text;
  v_existing_product_id bigint;
  v_new_product_id bigint;
  v_row dirac.product;
BEGIN
  /* normalize (trim whitespace + remove spaces/hyphens) */
  v_barcode := NULLIF(regexp_replace(btrim(p_barcode), '[\s-]+', '', 'g'), '');

  IF v_barcode IS NULL THEN
    RAISE EXCEPTION 'barcode must be non-empty';
  END IF;

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'name must be non-empty';
  END IF;

  /* Ideal scenario, if barcode already exists, update linked product */
  SELECT pb.product_id
    INTO v_existing_product_id
  FROM dirac.product_barcode pb
  WHERE pb.barcode = v_barcode;

  IF v_existing_product_id IS NOT NULL THEN
    UPDATE dirac.product p
    SET name = p_name,
        description = COALESCE(p_description, p.description)
    WHERE p.id = v_existing_product_id
    RETURNING * INTO v_row;

    RETURN v_row;
  END IF;

  /* Protocol for barcode not found. Create product row first. */
  INSERT INTO dirac.product (name, description)
  VALUES (p_name, p_description)
  RETURNING id INTO v_new_product_id;

  /* Now try to claim the barcode mapping. */
  BEGIN
    INSERT INTO dirac.product_barcode (barcode, product_id)
    VALUES (v_barcode, v_new_product_id);
  EXCEPTION
    WHEN unique_violation THEN
      /* Another concurrent transaction inserted the barcode mapping first. */
      /* Delete the product we created to avoid orphan rows. */
      DELETE FROM dirac.product WHERE id = v_new_product_id;

      /* Fetch the existing mapping and update that product instead. */
      SELECT pb.product_id
        INTO v_existing_product_id
      FROM dirac.product_barcode pb
      WHERE pb.barcode = v_barcode;

      UPDATE dirac.product p
      SET name = p_name,
          description = COALESCE(p_description, p.description)
      WHERE p.id = v_existing_product_id
      RETURNING * INTO v_row;

      RETURN v_row;
  END;

  /* If we got here, we successfully inserted mapping. Return the created product row. */
  SELECT *
    INTO v_row
  FROM dirac.product
  WHERE id = v_new_product_id;

  RETURN v_row;
END;
$$;
-- +goose StatementEnd

-- +goose Down
/* This rolls back to "no ingest_product function". */
DROP FUNCTION IF EXISTS dirac.ingest_product(text, text, text);