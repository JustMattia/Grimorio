-- ==============================================================================
-- SCHEMA COMPLETO DI PRODUZIONE PER GRIMORIO (SUPABASE)
-- ==============================================================================

-- 1. TABELLA PROFILI
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    username TEXT,
    avatar_url TEXT,
    colore_badge TEXT DEFAULT '#facc15',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_delete" ON public.profiles FOR DELETE TO authenticated USING (auth.uid() = id);

-- 2. TABELLA COLLEZIONI (GRIMORI)
CREATE TABLE IF NOT EXISTS public.collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT NOT NULL,
    descrizione TEXT,
    creato_da UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    visibilita TEXT DEFAULT 'privata' CHECK (visibilita IN ('privata', 'condivisa', 'pubblica')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.collections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "collections_select" ON public.collections FOR SELECT TO authenticated USING (
    creato_da = auth.uid() 
    OR visibilita IN ('condivisa', 'pubblica') 
    OR id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid())
);
CREATE POLICY "collections_insert" ON public.collections FOR INSERT TO authenticated WITH CHECK (creato_da = auth.uid());
CREATE POLICY "collections_update" ON public.collections FOR UPDATE TO authenticated USING (
    creato_da = auth.uid() 
    OR id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor'))
);
CREATE POLICY "collections_delete" ON public.collections FOR DELETE TO authenticated USING (creato_da = auth.uid());

-- 3. TABELLA MEMBRI COLLEZIONE
CREATE TABLE IF NOT EXISTS public.collection_members (
    collection_id UUID REFERENCES public.collections(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    ruolo TEXT NOT NULL DEFAULT 'collaboratore' CHECK (ruolo IN ('proprietario', 'gestore', 'collaboratore', 'spettatore', 'admin', 'editor', 'viewer')),
    invitato_da UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (collection_id, user_id)
);

ALTER TABLE public.collection_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "members_select" ON public.collection_members FOR SELECT TO authenticated USING (true);
CREATE POLICY "members_insert" ON public.collection_members FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "members_update" ON public.collection_members FOR UPDATE TO authenticated USING (true);
CREATE POLICY "members_delete" ON public.collection_members FOR DELETE TO authenticated USING (true);

-- 4. TABELLA PROPRIETARI CARTE
CREATE TABLE IF NOT EXISTS public.collection_owners (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id),
    nome TEXT NOT NULL,
    colore_badge TEXT DEFAULT '#facc15',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (collection_id, nome)
);

ALTER TABLE public.collection_owners ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owners_all" ON public.collection_owners FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 5. TABELLA CARTE NEL GRIMORIO
CREATE TABLE IF NOT EXISTS public.cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
    scryfall_id TEXT,
    nome TEXT NOT NULL,
    nome_inglese TEXT,
    set_codice TEXT,
    numero_collezione TEXT,
    rarita TEXT,
    finitura TEXT,
    condizione TEXT DEFAULT 'NM',
    lingua TEXT DEFAULT 'it',
    quantita INTEGER DEFAULT 1,
    prezzo_cardmarket NUMERIC(10, 2),
    prezzo_cardtrader NUMERIC(10, 2),
    immagine_url TEXT,
    owner_id UUID REFERENCES public.collection_owners(id) ON DELETE SET NULL,
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cards_select" ON public.cards FOR SELECT TO authenticated USING (
    collection_id IN (SELECT id FROM public.collections WHERE creato_da = auth.uid() OR visibilita IN ('condivisa', 'pubblica'))
    OR collection_id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid())
);
CREATE POLICY "cards_insert" ON public.cards FOR INSERT TO authenticated WITH CHECK (
    collection_id IN (SELECT id FROM public.collections WHERE creato_da = auth.uid())
    OR collection_id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor'))
);
CREATE POLICY "cards_update" ON public.cards FOR UPDATE TO authenticated USING (
    collection_id IN (SELECT id FROM public.collections WHERE creato_da = auth.uid())
    OR collection_id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor'))
);
CREATE POLICY "cards_delete" ON public.cards FOR DELETE TO authenticated USING (
    collection_id IN (SELECT id FROM public.collections WHERE creato_da = auth.uid())
    OR collection_id IN (SELECT collection_id FROM public.collection_members WHERE user_id = auth.uid() AND ruolo IN ('proprietario', 'gestore', 'collaboratore', 'admin', 'editor'))
);

-- 6. TABELLE MAZZI E CARTE MAZZI
CREATE TABLE IF NOT EXISTS public.decks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
    nome TEXT NOT NULL,
    formato TEXT DEFAULT 'commander',
    creato_da UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.deck_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_id UUID NOT NULL REFERENCES public.decks(id) ON DELETE CASCADE,
    card_id UUID NOT NULL REFERENCES public.cards(id) ON DELETE CASCADE,
    quantita INTEGER DEFAULT 1,
    sezione TEXT DEFAULT 'maindeck',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (deck_id, card_id, sezione)
);

ALTER TABLE public.decks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "decks_all" ON public.decks FOR ALL TO authenticated USING (true) WITH CHECK (true);

ALTER TABLE public.deck_cards ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deck_cards_all" ON public.deck_cards FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 7. TABELLA INVITI
CREATE TABLE IF NOT EXISTS public.collection_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES public.collections(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL,
    ruolo TEXT NOT NULL DEFAULT 'collaboratore' CHECK (ruolo IN ('gestore', 'collaboratore', 'spettatore', 'admin', 'editor', 'viewer')),
    creato_da UUID NOT NULL REFERENCES auth.users(id),
    scade_il TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days'),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.collection_invites ENABLE ROW LEVEL SECURITY;
CREATE POLICY "invites_select" ON public.collection_invites FOR SELECT TO authenticated, anon USING (true);
CREATE POLICY "invites_all" ON public.collection_invites FOR ALL TO authenticated USING (true) WITH CHECK (true);
