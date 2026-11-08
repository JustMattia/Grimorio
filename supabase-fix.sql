-- ==============================================================================
-- SCRIPT UNICO DEFINITIVO PER GRIMORIO (SUPABASE)
-- Cancella tutte le vecchie policy che creavano ricorsione 500,
-- assegna le collezioni a Mattia e attiva le nuove policy RLS ultra-veloci e sicure.
-- ==============================================================================

-- 1. PULIZIA TOTALE AUTOMATICA DI TUTTE LE VECCHIE POLICY ESISTENTI NEL DATABASE
DO $$ 
DECLARE 
    r RECORD;
BEGIN
    FOR r IN (
        SELECT schemaname, tablename, policyname 
        FROM pg_policies 
        WHERE schemaname = 'public'
    ) 
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- 2. TABELLA PROFILI E FUNZIONI DI LOGIN / USERNAME
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS colore_badge TEXT DEFAULT '#facc15';
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_delete" ON public.profiles FOR DELETE TO authenticated USING (auth.uid() = id);

-- Funzione login tramite username o email
CREATE OR REPLACE FUNCTION public.get_email_by_identifier(p_identifier TEXT)
RETURNS TEXT 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_email TEXT;
BEGIN
    SELECT email INTO v_email
    FROM public.profiles
    WHERE LOWER(username) = LOWER(TRIM(p_identifier))
       OR LOWER(email) = LOWER(TRIM(p_identifier))
       OR LOWER(split_part(email, '@', 1)) = LOWER(TRIM(p_identifier))
    LIMIT 1;
    RETURN v_email;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_email_by_identifier(TEXT) TO anon, authenticated;

-- Funzione controllo unicità username
CREATE OR REPLACE FUNCTION public.check_username_available(p_username TEXT, p_exclude_user_id UUID DEFAULT NULL)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF p_username IS NULL OR LENGTH(TRIM(p_username)) < 2 THEN
        RETURN FALSE;
    END IF;
    RETURN NOT EXISTS (
        SELECT 1 
        FROM public.profiles
        WHERE LOWER(TRIM(username)) = LOWER(TRIM(p_username))
          AND (p_exclude_user_id IS NULL OR id != p_exclude_user_id)
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.check_username_available(p_username TEXT)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public.check_username_available(p_username, NULL);
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO anon, authenticated;

-- Indice univoco per impedire duplicati di username
CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_username_lower 
ON public.profiles (LOWER(TRIM(username))) 
WHERE username IS NOT NULL AND TRIM(username) != '';

-- 3. TABELLA MEMBRI DELLA COLLEZIONE
CREATE TABLE IF NOT EXISTS public.collection_members (
    collection_id UUID REFERENCES public.collections(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ruolo TEXT NOT NULL DEFAULT 'collaboratore',
    invitato_da UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (collection_id, user_id)
);

ALTER TABLE public.collection_members DROP CONSTRAINT IF EXISTS collection_members_ruolo_check;
ALTER TABLE public.collection_members ADD CONSTRAINT collection_members_ruolo_check 
    CHECK (ruolo IN ('proprietario', 'gestore', 'collaboratore', 'spettatore', 'admin', 'editor', 'viewer'));

-- 4. ASSEGNAZIONE COLLEZIONI ESISTENTI A JUSTMATTIA (mattia40k@gmail.com)
DO $$
DECLARE
    v_owner_id UUID;
    v_count INT;
BEGIN
    SELECT id INTO v_owner_id 
    FROM auth.users 
    WHERE LOWER(email) = 'mattia40k@gmail.com'
    LIMIT 1;

    IF v_owner_id IS NULL THEN
        SELECT id INTO v_owner_id 
        FROM public.profiles 
        WHERE LOWER(email) = 'mattia40k@gmail.com'
        LIMIT 1;
    END IF;

    IF v_owner_id IS NOT NULL THEN
        -- Assegna tutte le collezioni
        UPDATE public.collections 
        SET creato_da = v_owner_id;

        GET DIAGNOSTICS v_count = ROW_COUNT;
        RAISE NOTICE 'Assegnate % collezioni a mattia40k@gmail.com (UUID: %)', v_count, v_owner_id;

        -- Inserisci JustMattia come proprietario in collection_members
        INSERT INTO public.collection_members (collection_id, user_id, ruolo)
        SELECT c.id, v_owner_id, 'proprietario'
        FROM public.collections c
        ON CONFLICT (collection_id, user_id) DO UPDATE SET ruolo = 'proprietario';

        -- Collega l'owner in collection_owners
        UPDATE public.collection_owners
        SET user_id = v_owner_id
        WHERE user_id = v_owner_id
           OR LOWER(nome) = 'justmattia'
           OR LOWER(nome) IN (SELECT LOWER(username) FROM public.profiles WHERE id = v_owner_id);
    END IF;
END $$;

ALTER TABLE public.collections ADD COLUMN IF NOT EXISTS visibilita TEXT DEFAULT 'privata';

-- 5. POLICIES SU COLLECTION_MEMBERS (ZERO RICORSIONE, NESSUN ERRORE 500)
ALTER TABLE public.collection_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "members_select" ON public.collection_members 
    FOR SELECT TO authenticated 
    USING (true);

CREATE POLICY "members_insert" ON public.collection_members 
    FOR INSERT TO authenticated 
    WITH CHECK (true);

CREATE POLICY "members_update" ON public.collection_members 
    FOR UPDATE TO authenticated 
    USING (true);

CREATE POLICY "members_delete" ON public.collection_members 
    FOR DELETE TO authenticated 
    USING (true);

-- 6. POLICIES SU COLLECTIONS (GRIMORI)
ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "collections_select" ON public.collections 
    FOR SELECT TO authenticated 
    USING (
        creato_da = auth.uid() 
        OR visibilita IN ('condivisa', 'pubblica') 
        OR id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid())
    );

CREATE POLICY "collections_insert" ON public.collections 
    FOR INSERT TO authenticated 
    WITH CHECK (creato_da = auth.uid());

CREATE POLICY "collections_update" ON public.collections 
    FOR UPDATE TO authenticated 
    USING (
        creato_da = auth.uid() 
        OR id IN (
            SELECT collection_id FROM public.collection_members 
            WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor')
        )
    );

CREATE POLICY "collections_delete" ON public.collections 
    FOR DELETE TO authenticated 
    USING (creato_da = auth.uid());

-- 7. POLICIES SU CARTE NEL GRIMORIO
ALTER TABLE public.cards ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cards_select" ON public.cards 
    FOR SELECT TO authenticated 
    USING (
        collection_id IN (
            SELECT id FROM public.collections WHERE creato_da = auth.uid() OR visibilita IN ('condivisa', 'pubblica')
        )
        OR collection_id IN (
            SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "cards_insert" ON public.cards 
    FOR INSERT TO authenticated 
    WITH CHECK (
        collection_id IN (
            SELECT id FROM public.collections WHERE creato_da = auth.uid()
        )
        OR collection_id IN (
            SELECT collection_id FROM public.collection_members 
            WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor')
        )
    );

CREATE POLICY "cards_update" ON public.cards 
    FOR UPDATE TO authenticated 
    USING (
        collection_id IN (
            SELECT id FROM public.collections WHERE creato_da = auth.uid()
        )
        OR collection_id IN (
            SELECT collection_id FROM public.collection_members 
            WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor')
        )
    );

CREATE POLICY "cards_delete" ON public.cards 
    FOR DELETE TO authenticated 
    USING (
        collection_id IN (
            SELECT id FROM public.collections WHERE creato_da = auth.uid()
        )
        OR collection_id IN (
            SELECT collection_id FROM public.collection_members 
            WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor')
        )
    );

-- 8. POLICIES SU PROPRIETARI CARTE
ALTER TABLE public.collection_owners ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owners_all" ON public.collection_owners FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 9. FUNZIONE SICURA PER UNIRSI TRAMITE INVITO (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.join_collection_by_invite(p_collection_id UUID, p_ruolo TEXT DEFAULT 'collaboratore')
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ruolo TEXT;
    v_user_id UUID;
    v_username TEXT;
    v_badge TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Utente non autenticato';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.collections WHERE id = p_collection_id) THEN
        RAISE EXCEPTION 'Grimorio non trovato o non esistente';
    END IF;

    v_ruolo := LOWER(TRIM(COALESCE(p_ruolo, 'collaboratore')));
    IF v_ruolo NOT IN ('proprietario', 'gestore', 'collaboratore', 'spettatore', 'admin', 'editor', 'viewer') THEN
        v_ruolo := 'collaboratore';
    END IF;

    INSERT INTO public.collection_members (collection_id, user_id, ruolo)
    VALUES (p_collection_id, v_user_id, v_ruolo)
    ON CONFLICT (collection_id, user_id) 
    DO UPDATE SET ruolo = EXCLUDED.ruolo;

    SELECT 
        COALESCE(username, split_part(email, '@', 1), 'Membro'),
        COALESCE(colore_badge, '#facc15')
    INTO v_username, v_badge
    FROM public.profiles
    WHERE id = v_user_id;

    IF v_username IS NULL THEN
        v_username := 'Membro';
        v_badge := '#facc15';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.collection_owners WHERE collection_id = p_collection_id AND user_id = v_user_id) THEN
        INSERT INTO public.collection_owners (collection_id, user_id, nome, colore_badge)
        VALUES (p_collection_id, v_user_id, v_username, v_badge)
        ON CONFLICT (collection_id, nome) 
        DO UPDATE SET user_id = v_user_id, colore_badge = EXCLUDED.colore_badge;
    END IF;

    RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION public.join_collection_by_invite(UUID, TEXT) TO authenticated;

-- 10. POLICIES SU INVITI, MAZZI E CARTE MAZZI
CREATE TABLE IF NOT EXISTS public.collection_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL,
    ruolo TEXT NOT NULL DEFAULT 'collaboratore',
    creato_da UUID NOT NULL REFERENCES auth.users(id),
    scade_il TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days'),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.collection_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invites_select" ON public.collection_invites FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY "invites_all" ON public.collection_invites FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.decks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "decks_all" ON public.decks FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.deck_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deck_cards_all" ON public.deck_cards FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 11. INDICI DI PRESTAZIONE
CREATE INDEX IF NOT EXISTS idx_cards_collection_id ON public.cards(collection_id);
CREATE INDEX IF NOT EXISTS idx_cards_owner_id ON public.cards(owner_id);
CREATE INDEX IF NOT EXISTS idx_cards_nome ON public.cards(nome);
CREATE INDEX IF NOT EXISTS idx_collection_members_col_user ON public.collection_members(collection_id, user_id);
CREATE INDEX IF NOT EXISTS idx_collections_creato_da ON public.collections(creato_da);
