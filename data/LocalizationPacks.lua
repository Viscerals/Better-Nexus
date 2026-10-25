-- Nexus: data/LocalizationPacks.lua
-- Optional Nexus presentation packs for core/Localization.lua (issue #123).
-- Data only: plain tables from a pack ID to the pack's own name (autonym)
-- and its entries, from a reviewed English key to text, with no function,
-- metatable or generated key. The one formatted entry, readout.charge_counts,
-- is a template: its placeholders and their count types are owned by the code
-- schema in core/Localization.lua, never by this data. core/Localization.lua
-- loads just after this file (Nexus.toc), checks every name and entry against
-- the same text contract as the English base (and a template against its
-- schema), and copies what it accepts once.
--
-- The pack IDs are the Nexus preference enum of data/DefaultProfile.lua
-- (uiLanguages). They are Nexus product choices, not game client locales,
-- GetLocale() results or aliases; the game's own language is never read or
-- changed.
--
-- Each pack holds exactly a bounded six-message cohort and nothing else: the
-- original three static status messages of issue #123 (reason.save_in_progress,
-- reason.list_preparing, reason.saved_data_reading: saving still in progress,
-- a list still being prepared, saved data being read) and issue #142's
-- "first cohort" of data/LocalizationEnglish.lua: the two planner wait
-- reasons (reason.wait_three_choices: waiting for the next three Echo
-- choices, not a ready board; reason.wait_pending_pick_count: the pending-pick
-- count is not known yet, which is not 0) and the compact charge row
-- readout.charge_counts (Banish, Reroll and Freeze counts, each placeholder
-- exactly once). "Echo" is kept as the game's English term. Every other
-- Nexus text stays English.
-- All wording is draft: the original three were drafted for issue #123 and
-- the newer three are machine-assisted drafts. Each has had a technical
-- review only; no competent human reviewer of each language has accepted it.

Nexus = Nexus or {}
Nexus.LocalizationPacks = {
    frFR = {
        name = "Français",
        entries = {
            ["reason.save_in_progress"] = "L'enregistrement est toujours en cours ; attendez son résultat final",
            ["reason.list_preparing"] = "Cette liste est encore en cours de préparation",
            ["reason.saved_data_reading"] = "Lecture de vos données enregistrées",
            ["reason.wait_three_choices"] = "En attente des trois prochains choix d'Echo",
            ["reason.wait_pending_pick_count"] = "en attente du nombre de choix restants",
            ["readout.charge_counts"] = "Ban:{banish} Rel:{reroll} Gel:{freeze}",
        },
    },
    deDE = {
        name = "Deutsch",
        entries = {
            ["reason.save_in_progress"] = "Speichern läuft noch; bitte auf das endgültige Ergebnis warten",
            ["reason.list_preparing"] = "Diese Liste wird noch vorbereitet",
            ["reason.saved_data_reading"] = "Gespeicherte Daten werden gelesen",
            ["reason.wait_three_choices"] = "Warten auf die nächsten drei Echo-Auswahlen",
            ["reason.wait_pending_pick_count"] = "warten auf die Anzahl ausstehender Auswahlen",
            ["readout.charge_counts"] = "Verb:{banish} Neu:{reroll} Einfr:{freeze}",
        },
    },
    esES = {
        name = "Español",
        entries = {
            ["reason.save_in_progress"] = "El guardado sigue en curso; espera a su resultado final",
            ["reason.list_preparing"] = "Esta lista aún se está preparando",
            ["reason.saved_data_reading"] = "Leyendo tus datos guardados",
            ["reason.wait_three_choices"] = "Esperando las próximas tres opciones de Echo",
            ["reason.wait_pending_pick_count"] = "esperando el número de elecciones pendientes",
            ["readout.charge_counts"] = "Dest:{banish} Rel:{reroll} Cong:{freeze}",
        },
    },
    plPL = {
        name = "Polski",
        entries = {
            ["reason.save_in_progress"] = "Zapisywanie nadal trwa; poczekaj na ostateczny wynik",
            ["reason.list_preparing"] = "Ta lista jest jeszcze przygotowywana",
            ["reason.saved_data_reading"] = "Odczytywanie zapisanych danych",
            ["reason.wait_three_choices"] = "Oczekiwanie na kolejne trzy wybory Echo",
            ["reason.wait_pending_pick_count"] = "oczekiwanie na liczbę pozostałych wyborów",
            ["readout.charge_counts"] = "Wygn:{banish} Przel:{reroll} Zamr:{freeze}",
        },
    },
    ptBR = {
        name = "Português (Brasil)",
        entries = {
            ["reason.save_in_progress"] = "O salvamento ainda está em andamento; aguarde o resultado final",
            ["reason.list_preparing"] = "Esta lista ainda está sendo preparada",
            ["reason.saved_data_reading"] = "Lendo seus dados salvos",
            ["reason.wait_three_choices"] = "Aguardando as próximas três escolhas de Echo",
            ["reason.wait_pending_pick_count"] = "aguardando a contagem de escolhas pendentes",
            ["readout.charge_counts"] = "Banir:{banish} Rolar:{reroll} Cong:{freeze}",
        },
    },
    ruRU = {
        name = "Русский",
        entries = {
            ["reason.save_in_progress"] = "Сохранение ещё выполняется; дождитесь окончательного результата",
            ["reason.list_preparing"] = "Этот список ещё подготавливается",
            ["reason.saved_data_reading"] = "Чтение сохранённых данных",
            ["reason.wait_three_choices"] = "Ожидание следующих трёх вариантов Echo",
            ["reason.wait_pending_pick_count"] = "ожидание числа оставшихся выборов",
            ["readout.charge_counts"] = "Изг:{banish} Пер:{reroll} Зам:{freeze}",
        },
    },
}
