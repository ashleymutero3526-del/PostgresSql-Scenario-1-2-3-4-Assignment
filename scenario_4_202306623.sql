-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 4: Campus Clinic Medicine Dispensing
-- Student Number: 202409469

DROP TABLE IF EXISTS dispensing_records;
DROP TABLE IF EXISTS medicines;

-- 1. Tables and sample data
CREATE TABLE medicines (
    medicine_id    SERIAL PRIMARY KEY,
    medicine_name  VARCHAR(100) NOT NULL,
    stock_quantity INT NOT NULL CHECK (stock_quantity >= 0)
);

CREATE TABLE dispensing_records (
    record_id      SERIAL PRIMARY KEY,
    medicine_id    INT NOT NULL REFERENCES medicines(medicine_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(10) NOT NULL DEFAULT 'DISPENSED'
                   CHECK (status IN ('DISPENSED','REVERSED')),
    dispensed_at   TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO medicines (medicine_name, stock_quantity) VALUES
    ('Paracetamol 500mg', 100),
    ('Amoxicillin 250mg', 15),
    ('Oral Rehydration Salts', 0);

SELECT * FROM medicines ORDER BY medicine_id;

-- 2. IF / ELSIF / ELSE: stock status
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT medicine_name, stock_quantity FROM medicines ORDER BY medicine_id LOOP
        IF rec.stock_quantity = 0 THEN
            RAISE NOTICE '% : OUT OF STOCK', rec.medicine_name;
        ELSIF rec.stock_quantity <= 20 THEN
            RAISE NOTICE '% : LOW on stock (%)', rec.medicine_name, rec.stock_quantity;
        ELSE
            RAISE NOTICE '% : sufficiently stocked (%)', rec.medicine_name, rec.stock_quantity;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE and numeric FOR
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Stock review day %', d;
        d := d + 1;
    END LOOP;

    FOR s IN 1..3 LOOP
        RAISE NOTICE 'Shelf inspection number %', s;
    END LOOP;
END $$;

-- 4. dispense_medicine procedure
CREATE OR REPLACE PROCEDURE dispense_medicine(p_medicine_id INT, p_student VARCHAR, p_qty INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid dispensing quantity: % (must be greater than zero)', p_qty;
    END IF;

    SELECT stock_quantity INTO v_stock
    FROM medicines WHERE medicine_id = p_medicine_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medicine % does not exist', p_medicine_id;
    END IF;

    IF v_stock < p_qty THEN
        RAISE NOTICE 'REJECTED: % units of medicine % requested for student % but only % in stock',
                     p_qty, p_medicine_id, p_student, v_stock;
        RETURN;
    END IF;

    UPDATE medicines SET stock_quantity = stock_quantity - p_qty WHERE medicine_id = p_medicine_id;
    INSERT INTO dispensing_records (medicine_id, student_number, quantity)
    VALUES (p_medicine_id, p_student, p_qty);
    RAISE NOTICE 'Dispensed % unit(s) of medicine % to student %', p_qty, p_medicine_id, p_student;
END;
$$;

-- 5. Two valid quantities and one exceeding stock
CALL dispense_medicine(1, 'S3001', 10);   -- valid
CALL dispense_medicine(2, 'S3002', 5);    -- valid
CALL dispense_medicine(2, 'S3003', 50);   -- exceeds stock (rejected)

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 6. reverse_dispensing procedure
CREATE OR REPLACE PROCEDURE reverse_dispensing(p_record_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_medicine_id INT;
    v_qty         INT;
    v_status      VARCHAR(10);
BEGIN
    SELECT medicine_id, quantity, status INTO v_medicine_id, v_qty, v_status
    FROM dispensing_records WHERE record_id = p_record_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Dispensing record % does not exist', p_record_id;
    END IF;

    IF v_status = 'REVERSED' THEN
        RAISE NOTICE 'Record % already reversed; stock NOT restored again', p_record_id;
        RETURN;
    END IF;

    UPDATE dispensing_records SET status = 'REVERSED' WHERE record_id = p_record_id;
    UPDATE medicines SET stock_quantity = stock_quantity + v_qty WHERE medicine_id = v_medicine_id;
    RAISE NOTICE 'Record % reversed; % unit(s) restored to stock', p_record_id, v_qty;
END;
$$;

CALL reverse_dispensing(1);   -- first call restores stock
CALL reverse_dispensing(1);   -- second call must not restore again

SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;

-- 7. Explicit (parameterised) cursor: medicines below a low-stock threshold
DO $$
DECLARE
    cur_low CURSOR (p_threshold INT) FOR
        SELECT medicine_id, medicine_name, stock_quantity
        FROM medicines WHERE stock_quantity < p_threshold ORDER BY stock_quantity;
    v_id    INT;
    v_name  VARCHAR;
    v_stock INT;
BEGIN
    OPEN cur_low(20);   -- threshold = 20 units
    LOOP
        FETCH cur_low INTO v_id, v_name, v_stock;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Below threshold: [%] % -> % in stock', v_id, v_name, v_stock;
    END LOOP;
    CLOSE cur_low;
END $$;

-- 8. Negative quantity: handled with an EXCEPTION block
DO $$
BEGIN
    CALL dispense_medicine(1, 'S3004', -5);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM medicines ORDER BY medicine_id;
SELECT * FROM dispensing_records ORDER BY record_id;
