-- +goose Up
-- +goose StatementBegin

CREATE TABLE IF NOT EXISTS dirac.flagged_barcode (
  id BIGSERIAL PRIMARY KEY,
  raw_barcode TEXT NOT NULL,
  cleaned_barcode TEXT NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_flagged_barcode_raw
  ON dirac.flagged_barcode(raw_barcode);

CREATE INDEX IF NOT EXISTS idx_flagged_barcode_created_at
  ON dirac.flagged_barcode(created_at);

-- +goose StatementEnd
-- +goose Down
DROP TABLE IF EXISTS dirac.flagged_barcode;