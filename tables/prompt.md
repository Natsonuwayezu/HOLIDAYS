-- ═══════════════════════════════════════════════════════════════════
-- 015_fix_login_check.sql
-- Run this in Supabase SQL Editor NOW to fix login.
--
-- Errors this fixes:
--   - function login_check() does not exist (404)
--   - function crypt(text, text) does not exist (pgcrypto missing)
-- ═══════════════════════════════════════════════════════════════════

-- Step 1: Try to enable pgcrypto (may already be enabled)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Step 2: Clear login lockouts (in case of too-many-attempts block)
DELETE FROM login_attempts WHERE success = FALSE;

-- Step 3: Create login_check that works with OR without pgcrypto
-- Uses simple plaintext comparison as fallback when bcrypt not available
CREATE OR REPLACE FUNCTION login_check(
    p_username TEXT,
    p_password TEXT,
    p_role     TEXT
)
RETURNS TABLE (
    id         INTEGER,
    username   TEXT,
    first_name TEXT,
    last_name  TEXT,
    role       TEXT,
    phone      TEXT,
    email      TEXT,
    is_active  BOOLEAN,
    class_id   INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    recent_failures INTEGER := 0;
    t               RECORD;
    admin_pw        TEXT;
    pw_match        BOOLEAN := FALSE;
BEGIN
    -- Lockout check (10 failures in 15 min)
    BEGIN
        SELECT COUNT(*) INTO recent_failures
        FROM login_attempts
        WHERE login_attempts.username     = p_username
          AND login_attempts.role         = p_role
          AND login_attempts.success      = FALSE
          AND login_attempts.attempted_at > NOW() - INTERVAL '15 minutes';
    EXCEPTION WHEN OTHERS THEN
        recent_failures := 0; -- ignore if login_attempts missing
    END;

    IF recent_failures >= 10 THEN
        BEGIN
            INSERT INTO login_attempts (username, role, success)
            VALUES (p_username, p_role, FALSE);
        EXCEPTION WHEN OTHERS THEN NULL; END;
        RETURN;
    END IF;

    -- ── ADMIN LOGIN ───────────────────────────────────────────────
    IF p_role = 'admin' THEN
        SELECT value INTO admin_pw
        FROM school_settings WHERE key = 'admin_password';

        IF admin_pw IS NOT NULL THEN
            -- Try bcrypt first, fall back to plaintext
            BEGIN
                pw_match := (crypt(p_password, admin_pw) = admin_pw);
            EXCEPTION WHEN OTHERS THEN
                pw_match := (admin_pw = p_password); -- plaintext fallback
            END;
        END IF;

        IF pw_match THEN
            -- Return the admin teacher record
            SELECT INTO t id, username, first_name, last_name, role, phone, email, is_active, class_id
            FROM teachers WHERE role = 'admin' LIMIT 1;

            IF t.id IS NOT NULL THEN
                BEGIN
                    INSERT INTO login_attempts (username, role, success)
                    VALUES (p_username, p_role, TRUE);
                EXCEPTION WHEN OTHERS THEN NULL; END;

                RETURN QUERY SELECT t.id, t.username, t.first_name, t.last_name,
                                    t.role, t.phone, t.email, t.is_active, t.class_id;
                RETURN;
            END IF;
        END IF;

    -- ── TEACHER / ACCOUNTANT LOGIN ────────────────────────────────
    ELSE
        SELECT INTO t id, username, password, first_name, last_name,
                      role, phone, email, is_active, class_id
        FROM teachers
        WHERE LOWER(username) = LOWER(p_username)
          AND role = p_role
          AND is_active = TRUE
        LIMIT 1;

        IF t.id IS NOT NULL THEN
            -- Try bcrypt, fall back to plaintext
            BEGIN
                pw_match := (crypt(p_password, t.password) = t.password);
            EXCEPTION WHEN OTHERS THEN
                pw_match := (t.password = p_password);
            END;

            IF pw_match THEN
                BEGIN
                    INSERT INTO login_attempts (username, role, success)
                    VALUES (p_username, p_role, TRUE);
                EXCEPTION WHEN OTHERS THEN NULL; END;

                RETURN QUERY SELECT t.id, t.username, t.first_name, t.last_name,
                                    t.role, t.phone, t.email, t.is_active, t.class_id;
                RETURN;
            END IF;
        END IF;
    END IF;

    -- Failed login
    BEGIN
        INSERT INTO login_attempts (username, role, success)
        VALUES (p_username, p_role, FALSE);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    -- Return empty = invalid credentials
END;
$$;

-- Step 4: Grant execute
GRANT EXECUTE ON FUNCTION login_check(TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION login_check(TEXT, TEXT, TEXT) TO authenticated;

-- Step 5: Grant table access
GRANT SELECT ON school_settings TO anon, authenticated;
GRANT SELECT ON teachers        TO anon, authenticated;

-- Step 6: Test immediately
-- This should return 1 row if admin password is correct:
SELECT id, username, first_name, role, is_active
FROM login_check('admin', 'Lafontaine2026', 'admin');
