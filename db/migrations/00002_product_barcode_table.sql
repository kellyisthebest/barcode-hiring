-- +goose Up

/* This table links barcodes to products. We separate this out from the main product table to 
 allow for multiple barcodes per product in the future if needed. */

CREATE TABLE IF NOT EXISTS dirac.product_barcode (
    barcode TEXT PRIMARY KEY,
    product_id BIGINT NOT NULL REFERENCES dirac.product(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_product_barcode_product_id
  ON dirac.product_barcode(product_id);

-- +goose Down

DROP TABLE IF EXISTS dirac.product_barcode;