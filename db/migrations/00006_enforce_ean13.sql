-- +goose Up
-- +goose StatementBegin

ALTER TABLE dirac.product_barcode
  ALTER COLUMN barcode TYPE dirac.ean13
  USING dirac.normalize_to_ean13(barcode);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin

ALTER TABLE dirac.product_barcode
  ALTER COLUMN barcode TYPE text;

-- +goose StatementEnd