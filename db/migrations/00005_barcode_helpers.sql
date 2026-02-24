-- +goose Up
-- +goose StatementBegin

/*Compute the EAN-13 check digit from 12-digit base */
/* https://www.youtube.com/watch?v=XPuTZMp-HE8 this video has a good explanation of the EAN-13 check digit algorithm */

CREATE OR REPLACE FUNCTION dirac.ean13_check_digit(p12 text)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  WITH d AS (
    SELECT
      gs.i,
      substr(p12, gs.i, 1)::int AS digit
    FROM generate_series(1, 12) AS gs(i)
  ),
  s AS (
    SELECT
      sum(CASE WHEN (i % 2) = 1 THEN digit ELSE 0 END) AS sum_odd,
      sum(CASE WHEN (i % 2) = 0 THEN digit ELSE 0 END) AS sum_even
    FROM d
  )
  SELECT (10 - ((sum_odd + 3*sum_even) % 10)) % 10
  FROM s;
$$;

/* Validate full 13-digit EAN by checking that the last digit matches the computed check digit from the first 12 digits. */
CREATE OR REPLACE FUNCTION dirac.is_valid_ean13(p13 text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p13 ~ '^\d{13}$'
    AND right(p13, 1)::int = dirac.ean13_check_digit(left(p13, 12));
$$;

/*  Normalize input barcode (UPC-A -> EAN-13 by left-padding '0')
    Allows spaces/hyphens in input, rejects other characters.
    Accepts:
      - 11 digits (UPC without check digit): computes check digit, then returns EAN-13
      - 12 digits (UPC-A): pads 0 -> EAN-13 and validates check digit
      - 13 digits (EAN-13): validates check digit */
CREATE OR REPLACE FUNCTION dirac.normalize_to_ean13(p_barcode text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text;
  v12 text;
  cd int;
BEGIN
  IF p_barcode IS NULL THEN
    RAISE EXCEPTION 'barcode must be non-empty'
      USING ERRCODE = '22023';
  END IF;

  /* Trim, remove whitespaces + hyphens only (do NOT silently drop other characters) */
  v := regexp_replace(btrim(p_barcode), '[\s-]+', '', 'g');
  v := NULLIF(v, '');

  IF v IS NULL THEN
    RAISE EXCEPTION 'barcode must be non-empty'
      USING ERRCODE = '22023';
  END IF;

  IF v !~ '^\d+$' THEN
    RAISE EXCEPTION 'barcode must contain only digits, spaces, or hyphens'
      USING ERRCODE = '22023';
  END IF;

  IF length(v) = 11 THEN
    -- UPC (no check digit) -> build 12-digit EAN base by prepending 0
    v12 := '0' || v;
    cd := dirac.ean13_check_digit(v12);
    RETURN v12 || cd::text;

  ELSIF length(v) = 12 THEN
    -- UPC-A -> EAN-13 by prepending 0; validate check digit via EAN-13 rule
    IF NOT dirac.is_valid_ean13('0' || v) THEN
      RAISE EXCEPTION 'invalid UPC/EAN check digit'
        USING ERRCODE = '22023';
    END IF;
    RETURN '0' || v;

  ELSIF length(v) = 13 THEN
    -- EAN-13
    IF NOT dirac.is_valid_ean13(v) THEN
      RAISE EXCEPTION 'invalid EAN-13 check digit'
        USING ERRCODE = '22023';
    END IF;
    RETURN v;

  ELSE
    RAISE EXCEPTION 'barcode must be 11 (UPC w/o check), 12 (UPC-A), or 13 (EAN-13) digits after removing spaces/hyphens'
      USING ERRCODE = '22023';
  END IF;
END;
$$;

/* Domain for canonical storage */
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'dirac' AND t.typname = 'ean13'
  ) THEN
    EXECUTE $d$
      CREATE DOMAIN dirac.ean13 AS text
      CHECK (VALUE ~ '^\d{13}$' AND dirac.is_valid_ean13(VALUE));
    $d$;
  END IF;
END $$;

-- +goose StatementEnd
-- +goose Down
DROP DOMAIN IF EXISTS dirac.ean13;
DROP FUNCTION IF EXISTS dirac.normalize_to_ean13(text);
DROP FUNCTION IF EXISTS dirac.is_valid_ean13(text);
DROP FUNCTION IF EXISTS dirac.ean13_check_digit(text);