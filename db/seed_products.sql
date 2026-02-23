/* Background for different types of barcodes:
- UPC (Universal Product Code): 12 digits, common in North America for retail products.
- EAN (European Article Number): 13 digits, used internationally for retail products. EAN-8 is a shorter version with 8 digits.
- ISBN (International Standard Book Number): 13 digits (previously 10), used for
    books. ISBN-13 is compatible with EAN-13 and usually starts with '978' or '979'. */


BEGIN;

-- 1) Insert new product with a barcode that includes spaces/hyphen (tests normalization)
SELECT dirac.ingest_product(' 0123-456 ', 'Milk', '1L carton');

-- 2) Insert a different product (EAN-13 example)
SELECT dirac.ingest_product('5000112548167', 'VitHit', '500ml bottle');

-- 3) Re-ingest same barcode with different formatting (should dedupe to the same product)
-- Demonstrate an update safely: keep name the same, update description.
SELECT dirac.ingest_product(' 0 123 456 ', 'Milk', '1L carton (updated)');

-- 4) ISBN-13 example
SELECT dirac.ingest_product('9780143127741', 'Book example', 'ISBN-13 example');

COMMIT;

-- Verification queries (run this for the barcode_db >> docker compose exec db psql -U postgres -d barcode_db):
-- Show products
SELECT * FROM dirac.product ORDER BY id;

-- Show barcode mappings
SELECT * FROM dirac.product_barcode ORDER BY barcode;

-- Prove Milk deduped: barcode should map to exactly one product_id
SELECT
  pb.barcode,
  pb.product_id,
  p.name,
  p.description
FROM dirac.product_barcode pb
JOIN dirac.product p ON p.id = pb.product_id
WHERE pb.barcode = '0123456';