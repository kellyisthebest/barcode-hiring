-- +goose Up
-- +goose StatementBegin

/* This function ingests a product given a barcode, name, and optional description.
It normalizes the barcode by trimming whitespace and removing spaces/hyphens.
If the normalized barcode already exists, it updates the linked product's name and description (if provided).
If the barcode does not exist, it creates a new product and links it to the barcode. */

/* Note: not yet handeling duplicate key violations */

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
  v_product_id bigint;
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

  /* If barcode already exists, update the linked product */
  SELECT pb.product_id
    INTO v_product_id
  FROM dirac.product_barcode pb
  WHERE pb.barcode = v_barcode;

  IF v_product_id IS NULL THEN
    /* create new product row */
    INSERT INTO dirac.product (name, description)
    VALUES (p_name, p_description)
    RETURNING * INTO v_row;

    /* link barcode -> product */
    INSERT INTO dirac.product_barcode (barcode, product_id)
    VALUES (v_barcode, v_row.id);

    RETURN v_row;
  ELSE
    /* update existing product row */
    UPDATE dirac.product p
    SET name = p_name,
        description = COALESCE(p_description, p.description)
    WHERE p.id = v_product_id
    RETURNING * INTO v_row;

    RETURN v_row;
  END IF;
END;
$$;
-- +goose StatementEnd

-- +goose Down
DROP FUNCTION IF EXISTS dirac.ingest_product(text, text, text);