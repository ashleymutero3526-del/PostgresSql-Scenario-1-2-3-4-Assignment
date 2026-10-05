-- ICT371 PostgreSQL Scenario Assignment
-- Scenario 3: Student Hostel Room Allocation
-- Student Number: 202409469

DROP TABLE IF EXISTS allocations;
DROP TABLE IF EXISTS hostel_rooms;

-- 1. Tables and sample data
CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_name        VARCHAR(50) NOT NULL,
    available_spaces INT NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INT NOT NULL REFERENCES hostel_rooms(room_id),
    status         VARCHAR(12) NOT NULL DEFAULT 'ALLOCATED'
                   CHECK (status IN ('ALLOCATED','CHECKED_OUT')),
    allocated_at   TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO hostel_rooms (room_name, available_spaces) VALUES
    ('Room A101', 4),
    ('Room A102', 1),
    ('Room B201', 0);

SELECT * FROM hostel_rooms ORDER BY room_id;

-- 2. IF / ELSIF / ELSE: room occupancy report
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT room_name, available_spaces FROM hostel_rooms ORDER BY room_id LOOP
        IF rec.available_spaces = 0 THEN
            RAISE NOTICE '% : FULL', rec.room_name;
        ELSIF rec.available_spaces = 1 THEN
            RAISE NOTICE '% : one space left', rec.room_name;
        ELSE
            RAISE NOTICE '% : several spaces (%)', rec.room_name, rec.available_spaces;
        END IF;
    END LOOP;
END $$;

-- 3. WHILE and numeric FOR
DO $$
DECLARE
    d INT := 1;
BEGIN
    WHILE d <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day %', d;
        d := d + 1;
    END LOOP;

    FOR chk IN 1..3 LOOP
        RAISE NOTICE 'Room check number %', chk;
    END LOOP;
END $$;

-- 4. allocate_room procedure
CREATE OR REPLACE PROCEDURE allocate_room(p_student VARCHAR, p_room_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_spaces INT;
BEGIN
    IF p_student IS NULL OR btrim(p_student) = '' THEN
        RAISE EXCEPTION 'Invalid input: student number cannot be blank';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room % does not exist', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE NOTICE 'REJECTED: room % is full; student % not allocated', p_room_id, p_student;
        RETURN;
    END IF;

    UPDATE hostel_rooms SET available_spaces = available_spaces - 1 WHERE room_id = p_room_id;
    INSERT INTO allocations (student_number, room_id) VALUES (btrim(p_student), p_room_id);
    RAISE NOTICE 'Student % allocated to room %', p_student, p_room_id;
END;
$$;

-- 5. Two valid allocations and one to a full room
CALL allocate_room('S2001', 1);   -- valid
CALL allocate_room('S2002', 2);   -- valid (room becomes full)
CALL allocate_room('S2003', 3);   -- room already full (rejected)

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out procedure
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_room_id INT;
    v_status  VARCHAR(12);
BEGIN
    SELECT room_id, status INTO v_room_id, v_status
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Allocation % does not exist', p_allocation_id;
    END IF;

    IF v_status = 'CHECKED_OUT' THEN
        RAISE NOTICE 'Allocation % already checked out; no extra space freed', p_allocation_id;
        RETURN;
    END IF;

    UPDATE allocations SET status = 'CHECKED_OUT' WHERE allocation_id = p_allocation_id;
    UPDATE hostel_rooms SET available_spaces = available_spaces + 1 WHERE room_id = v_room_id;
    RAISE NOTICE 'Allocation % checked out; one space released in room %', p_allocation_id, v_room_id;
END;
$$;

CALL check_out(1);   -- first call frees a space
CALL check_out(1);   -- second call must not free another

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 7. Explicit cursor: full or nearly full rooms
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_id, room_name, available_spaces
        FROM hostel_rooms WHERE available_spaces <= 1 ORDER BY available_spaces;
    v_id     INT;
    v_name   VARCHAR;
    v_spaces INT;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO v_id, v_name, v_spaces;
        EXIT WHEN NOT FOUND;
        IF v_spaces = 0 THEN
            RAISE NOTICE '[%] % is FULL', v_id, v_name;
        ELSE
            RAISE NOTICE '[%] % is nearly full (% space left)', v_id, v_name, v_spaces;
        END IF;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- 8. Blank student number: handled with an EXCEPTION block
DO $$
BEGIN
    CALL allocate_room('   ', 1);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;
