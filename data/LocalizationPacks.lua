-- Nexus: data/LocalizationPacks.lua
-- Optional Nexus presentation packs for core/Localization.lua (issue #123).
-- Data only: plain tables from a pack ID to the pack's own name (autonym)
-- and its entries, from a reviewed English key to text, with no function,
-- metatable, placeholder or generated key. core/Localization.lua loads just
-- after this file (Nexus.toc), checks every name and entry against the same
-- text contract as the English base, and copies what it accepts once.
--
-- The pack IDs are the Nexus preference enum of data/DefaultProfile.lua
-- (uiLanguages). They are Nexus product choices, not game client locales,
-- GetLocale() results or aliases; the game's own language is never read or
-- changed.
--
-- Each pack holds only the first cohort: the three status reasons of
-- data/LocalizationEnglish.lua (saving still in progress, a list still being
-- prepared, saved data being read). Every other Nexus text stays English.
-- The wording was drafted for this slice and has had a technical review
-- only; no competent human reviewer of each language has accepted it.

Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    frFR = {
        name = "Français",
        entries = {
            ["reason.save_in_progress"] = "L'enregistrement est toujours en cours ; attendez son résultat final",
            ["reason.list_preparing"] = "Cette liste est encore en cours de préparation",
            ["reason.saved_data_reading"] = "Lecture de vos données enregistrées",
        },
    },
    deDE = {
        name = "Deutsch",
        entries = {
            ["reason.save_in_progress"] = "Speichern läuft noch; bitte auf das endgültige Ergebnis warten",
            ["reason.list_preparing"] = "Diese Liste wird noch vorbereitet",
            ["reason.saved_data_reading"] = "Gespeicherte Daten werden gelesen",
        },
    },
    esES = {
        name = "Español",
        entries = {
            ["reason.save_in_progress"] = "El guardado sigue en curso; espera a su resultado final",
            ["reason.list_preparing"] = "Esta lista aún se está preparando",
            ["reason.saved_data_reading"] = "Leyendo tus datos guardados",
        },
    },
    plPL = {
        name = "Polski",
        entries = {
            ["reason.save_in_progress"] = "Zapisywanie nadal trwa; poczekaj na ostateczny wynik",
            ["reason.list_preparing"] = "Ta lista jest jeszcze przygotowywana",
            ["reason.saved_data_reading"] = "Odczytywanie zapisanych danych",
        },
    },
    ptBR = {
        name = "Português (Brasil)",
        entries = {
            ["reason.save_in_progress"] = "O salvamento ainda está em andamento; aguarde o resultado final",
            ["reason.list_preparing"] = "Esta lista ainda está sendo preparada",
            ["reason.saved_data_reading"] = "Lendo seus dados salvos",
        },
    },
    ruRU = {
        name = "Русский",
        entries = {
            ["reason.save_in_progress"] = "Сохранение ещё выполняется; дождитесь окончательного результата",
            ["reason.list_preparing"] = "Этот список ещё подготавливается",
            ["reason.saved_data_reading"] = "Чтение сохранённых данных",
        },
    },
}
