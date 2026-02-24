/* 
Background barcode formats:
- UPC-A: 12 digits (common in North America). In this project, UPC-A is normalized to EAN-13 by prefixing '0'.
- EAN-13: 13 digits (international retail). Validated by check digit.
- EAN-8: 8 digits (valid format, but NOT supported by normalize_to_ean13 in this project) -> should be flagged.
- ISBN-13: 13 digits and EAN-13 compatible (often starts with 978/979) -> should be accepted if check digit is valid.

What this demonstrates:
1) Canonicalization: UPC-A (12 digits) is normalized to EAN-13 by prefixing '0'
2) Validation: EAN-13 / UPC-A check digits are enforced
3) Idempotency: re-ingesting the same barcode updates the existing product
4) Lenient ingest: unsupported/invalid barcodes still create products, and are quarantined in dirac.flagged_barcode
*/

BEGIN;

-- -------------------------------------------------------------------
-- 0) Reset to a deterministic demo state
-- -------------------------------------------------------------------
SELECT 'RESET: truncating tables' AS section;

TRUNCATE TABLE dirac.flagged_barcode RESTART IDENTITY;
TRUNCATE TABLE dirac.product_barcode;
TRUNCATE TABLE dirac.product RESTART IDENTITY CASCADE;

-- -------------------------------------------------------------------
-- 1) Happy path: valid UPC-A with formatting -> stored as canonical EAN-13
-- -------------------------------------------------------------------
SELECT 'HAPPY PATH: UPC-A -> EAN-13 canonicalization' AS section;

-- UPC-A 036000291452 is valid; canonical EAN-13 should be 0036000291452
SELECT dirac.ingest_product(' 0360-002-91452 ', 'Milk', '1L carton (UPC-A with formatting)');

-- -------------------------------------------------------------------
-- 2) Happy path: valid EAN-13 as-is
-- -------------------------------------------------------------------
SELECT 'HAPPY PATH: EAN-13 stored as-is' AS section;

SELECT dirac.ingest_product('5000112548167', 'VitHit', '500ml bottle (EAN-13)');

-- -------------------------------------------------------------------
-- 3) Idempotency: re-ingest same UPC-A in different format -> updates existing product
-- -------------------------------------------------------------------
SELECT 'IDEMPOTENCY: same barcode updates existing product' AS section;

SELECT dirac.ingest_product(' 0 360 002 91452 ', 'Milk', '1L carton (updated description)');

-- -------------------------------------------------------------------
-- 4) Happy path: ISBN-13 (EAN-13 compatible) accepted
-- -------------------------------------------------------------------
SELECT 'HAPPY PATH: ISBN-13 (EAN-13 compatible)' AS section;

SELECT dirac.ingest_product('9780143127741', 'Book example', 'ISBN-13 example');

-- -------------------------------------------------------------------
-- 5) Quarantine/flag cases (lenient ingest)
-- -------------------------------------------------------------------
SELECT 'QUARANTINE: unsupported/invalid barcodes are flagged but products are still created' AS section;

-- EAN-8 (valid format, but unsupported by normalize_to_ean13 in this project)
SELECT dirac.ingest_product('96385074', 'Small item (EAN-8)', 'Should be flagged until EAN-8 supported');

-- Invalid length
SELECT dirac.ingest_product('0123456', 'Bad barcode (7 digits)', 'Should be flagged');

-- Non-numeric characters
SELECT dirac.ingest_product('ABC-123-XYZ', 'Bad barcode (non-numeric)', 'Should be flagged');

-- Invalid check digit (UPC-A)
SELECT dirac.ingest_product('036000291453', 'Bad barcode (invalid check digit)', 'Should be flagged');

-- Missing barcode
SELECT dirac.ingest_product(NULL, 'No barcode product', 'Should be flagged as missing barcode');

COMMIT;

-- -------------------------------------------------------------------
-- 6) Demo outputs 
-- -------------------------------------------------------------------
SELECT 'RESULTS: products' AS section;
SELECT id, name, description, created_at FROM dirac.product ORDER BY id;

SELECT 'RESULTS: barcode mappings (canonical only)' AS section;
SELECT barcode::text AS barcode, product_id, created_at
FROM dirac.product_barcode
ORDER BY barcode;

SELECT 'RESULTS: quarantined inputs (flagged_barcode)' AS section;
SELECT id, raw_barcode, cleaned_barcode, reason, created_at
FROM dirac.flagged_barcode
ORDER BY id;

-- -------------------------------------------------------------------
-- 7) “Proof” queries to validate invariants and demonstrate the state of the database after the above operations
-- -------------------------------------------------------------------
SELECT 'PROOF: product -> barcode left join (who has a canonical barcode?)' AS section;
SELECT p.id, p.name, pb.barcode::text AS barcode
FROM dirac.product p
LEFT JOIN dirac.product_barcode pb ON pb.product_id = p.id
ORDER BY p.id;

SELECT 'PROOF: Milk canonical barcode maps to exactly one product' AS section;
SELECT pb.barcode::text AS barcode, pb.product_id, p.name, p.description
FROM dirac.product_barcode pb
JOIN dirac.product p ON p.id = pb.product_id
WHERE pb.barcode = '0036000291452';

SELECT 'PROOF: summary counts' AS section;
SELECT
  (SELECT count(*) FROM dirac.product)         AS products,
  (SELECT count(*) FROM dirac.product_barcode) AS mapped_barcodes,
  (SELECT count(*) FROM dirac.flagged_barcode) AS flagged_inputs;

-- Should return 0 rows: domain already enforces this, but good as a demo invariant.
SELECT 'INVARIANT: product_barcode contains only valid EAN-13' AS section;
SELECT *
FROM dirac.product_barcode
WHERE barcode::text !~ '^\d{13}$'
   OR NOT dirac.is_valid_ean13(barcode::text);

-- Should return 0 rows: barcode is a PK, but again nice for demo.
SELECT 'INVARIANT: no duplicate barcodes' AS section;
SELECT barcode::text AS barcode, count(*)
FROM dirac.product_barcode
GROUP BY barcode
HAVING count(*) > 1;