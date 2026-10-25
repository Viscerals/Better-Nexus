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
-- Each pack holds exactly 27 entries (26 static texts and one template) and
-- nothing else. The first six are the bounded six-message cohort: the
-- original three static status messages of issue #123 (reason.save_in_progress,
-- reason.list_preparing, reason.saved_data_reading: saving still in progress,
-- a list still being prepared, saved data being read) and issue #142's
-- "first cohort" of data/LocalizationEnglish.lua: the two planner wait
-- reasons (reason.wait_three_choices: waiting for the next three Echo
-- choices, not a ready board; reason.wait_pending_pick_count: the pending-pick
-- count is not known yet, which is not 0) and the compact charge row
-- readout.charge_counts (Banish, Reroll and Freeze counts, each placeholder
-- exactly once). The other 21 are issues #143/#148's static ui/Panel.lua
-- cohort (keys panel.*): My Builds navigation and its hover, the first-run
-- Assign Wishlist and Create Wishlist navigation and their hovers, the
-- PROGRESS, STILL NEEDED, EXTRA COPIES and LOCKED TARGETS headings, and the
-- complete locked-target hover. They keep every English consequence: a
-- different Saved Build chosen on My Builds changes the active loadout;
-- nothing is assigned before an explicit Wishlist choice; the editor opens a
-- draft that is saved or assigned only by Create & assign or Create
-- unassigned; a plan designs at most six target copies; the exact Echo and
-- quality come first; ownership is not locked-slot placement; locked slots
-- are not card Freeze. "Echo", "Nexus", the game terms Saved Build, Echo
-- Journal and Freeze, the game page label My Builds and the editor action
-- labels Create & assign and Create unassigned are kept in English. Every
-- other Nexus text stays English. Data presence alone does not prove that a
-- consumer shows these keys or that every window is covered.
-- All wording is draft: the original three were drafted for issue #123, and
-- the newer three and the 21 Panel texts are original machine-assisted
-- drafts (no imported translation corpus). Each has had a technical review
-- only; no competent human reviewer of each language has been assigned or
-- has accepted it. Client locale aliases, fonts, glyphs and layout fit are
-- not verified natively.

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
            ["panel.button.my_builds"] = "Mes builds",
            ["panel.tooltip.open_my_builds"] = "Ouvrir My Builds",
            ["panel.tooltip.my_builds_destination"] = "Ouvre la page My Builds du serveur. Y choisir un autre Saved Build change la configuration active.",
            ["panel.button.assign_wishlist"] = "Assigner une liste de souhaits",
            ["panel.tooltip.assignment_heading"] = "Assigner une liste de souhaits",
            ["panel.tooltip.assignment_chooser"] = "Ouvre l'Echo Journal avec son sélecteur de liste de souhaits pour cette configuration. Rien n'est assigné tant que vous n'y choisissez pas une liste de souhaits.",
            ["panel.button.create_wishlist"] = "Créer une liste de souhaits",
            ["panel.tooltip.create_wishlist_heading"] = "Importer ou créer une liste de souhaits",
            ["panel.tooltip.create_wishlist_source"] = "Collez une chaîne de liste de souhaits ou créez-en une directement dans Nexus.",
            ["panel.tooltip.create_wishlist_draft"] = "Ceci ouvre l'éditeur de liste de souhaits avec un brouillon. Rien n'est enregistré ni assigné tant que vous n'y appuyez pas sur Create & assign ou Create unassigned.",
            ["panel.heading.locked_targets"] = "CIBLES VERROUILLÉES",
            ["panel.tooltip.locked_remaining"] = "Cibles verrouillées restantes",
            ["panel.tooltip.locked_plan"] = "Ces cibles sont prévues pour vos emplacements d'Echo verrouillés (un plan prévoit au plus six copies cibles).",
            ["panel.tooltip.locked_acquire"] = "Obtenez d'abord l'Echo exact demandé, dans la qualité demandée.",
            ["panel.tooltip.locked_placement"] = "Les copies possédées doivent encore être placées dans des emplacements d'Echo verrouillés.",
            ["panel.tooltip.locked_not_freeze"] = "Les emplacements d'Echo verrouillés actuels et le Freeze des cartes sont distincts.",
            ["panel.tooltip.locked_acquire_list"] = "Encore à obtenir :",
            ["panel.tooltip.open_wishlist_editor"] = "Cliquez pour ouvrir l'éditeur de liste de souhaits",
            ["panel.heading.progress"] = "PROGRESSION",
            ["panel.heading.still_needed"] = "ENCORE REQUIS",
            ["panel.heading.extra_copies"] = "COPIES EN TROP",
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
            ["panel.button.my_builds"] = "Meine Builds",
            ["panel.tooltip.open_my_builds"] = "My Builds öffnen",
            ["panel.tooltip.my_builds_destination"] = "Öffnet die Serverseite My Builds. Die Wahl eines anderen Saved Build dort ändert die aktive Zusammenstellung.",
            ["panel.button.assign_wishlist"] = "Wunschliste zuweisen",
            ["panel.tooltip.assignment_heading"] = "Wunschliste zuweisen",
            ["panel.tooltip.assignment_chooser"] = "Öffnet das Echo Journal mit seiner Wunschlisten-Auswahl für diese Zusammenstellung. Nichts wird zugewiesen, bis du dort eine Wunschliste wählst.",
            ["panel.button.create_wishlist"] = "Wunschliste erstellen",
            ["panel.tooltip.create_wishlist_heading"] = "Wunschliste importieren oder erstellen",
            ["panel.tooltip.create_wishlist_source"] = "Füge eine Wunschlisten-Zeichenfolge ein oder erstelle eine direkt in Nexus.",
            ["panel.tooltip.create_wishlist_draft"] = "Dies öffnet den Wunschlisten-Editor mit einem Entwurf. Nichts wird gespeichert oder zugewiesen, bis du dort Create & assign oder Create unassigned drückst.",
            ["panel.heading.locked_targets"] = "GESPERRTE ZIELE",
            ["panel.tooltip.locked_remaining"] = "Verbleibende gesperrte Ziele",
            ["panel.tooltip.locked_plan"] = "Diese Ziele sind für deine gesperrten Echo-Plätze geplant (ein Plan sieht höchstens sechs Zielkopien vor).",
            ["panel.tooltip.locked_acquire"] = "Beschaffe zuerst genau das angeforderte Echo in genau der angeforderten Qualität.",
            ["panel.tooltip.locked_placement"] = "Besessene Kopien müssen noch in gesperrte Echo-Plätze gelegt werden.",
            ["panel.tooltip.locked_not_freeze"] = "Aktuelle gesperrte Echo-Plätze und Karten-Freeze sind voneinander getrennt.",
            ["panel.tooltip.locked_acquire_list"] = "Noch zu beschaffen:",
            ["panel.tooltip.open_wishlist_editor"] = "Klicken, um den Wunschlisten-Editor zu öffnen",
            ["panel.heading.progress"] = "FORTSCHRITT",
            ["panel.heading.still_needed"] = "NOCH BENÖTIGT",
            ["panel.heading.extra_copies"] = "ZUSÄTZLICHE KOPIEN",
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
            ["panel.button.my_builds"] = "Mis builds",
            ["panel.tooltip.open_my_builds"] = "Abrir My Builds",
            ["panel.tooltip.my_builds_destination"] = "Abre la página My Builds del servidor. Elegir allí otro Saved Build cambia la configuración activa.",
            ["panel.button.assign_wishlist"] = "Asignar lista de deseos",
            ["panel.tooltip.assignment_heading"] = "Asignar lista de deseos",
            ["panel.tooltip.assignment_chooser"] = "Abre el Echo Journal con su selector de lista de deseos para esta configuración. No se asigna nada hasta que elijas allí una lista de deseos.",
            ["panel.button.create_wishlist"] = "Crear lista de deseos",
            ["panel.tooltip.create_wishlist_heading"] = "Importar o crear una lista de deseos",
            ["panel.tooltip.create_wishlist_source"] = "Pega una cadena de lista de deseos o crea una directamente en Nexus.",
            ["panel.tooltip.create_wishlist_draft"] = "Esto abre el editor de listas de deseos con un borrador. No se guarda ni se asigna nada hasta que pulses allí Create & assign o Create unassigned.",
            ["panel.heading.locked_targets"] = "OBJETIVOS BLOQUEADOS",
            ["panel.tooltip.locked_remaining"] = "Objetivos bloqueados restantes",
            ["panel.tooltip.locked_plan"] = "Estos objetivos están planeados para tus espacios de Echo bloqueados (un plan diseña como máximo seis copias objetivo).",
            ["panel.tooltip.locked_acquire"] = "Consigue primero exactamente el Echo y la calidad solicitados.",
            ["panel.tooltip.locked_placement"] = "Las copias que posees aún deben colocarse en espacios de Echo bloqueados.",
            ["panel.tooltip.locked_not_freeze"] = "Los espacios de Echo bloqueados actuales y el Freeze de cartas son cosas distintas.",
            ["panel.tooltip.locked_acquire_list"] = "Aún falta conseguir:",
            ["panel.tooltip.open_wishlist_editor"] = "Haz clic para abrir el editor de listas de deseos",
            ["panel.heading.progress"] = "PROGRESO",
            ["panel.heading.still_needed"] = "AÚN NECESARIO",
            ["panel.heading.extra_copies"] = "COPIAS EXTRA",
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
            ["panel.button.my_builds"] = "Moje buildy",
            ["panel.tooltip.open_my_builds"] = "Otwórz My Builds",
            ["panel.tooltip.my_builds_destination"] = "Otwiera stronę serwera My Builds. Wybranie tam innego Saved Build zmienia aktywny zestaw.",
            ["panel.button.assign_wishlist"] = "Przypisz listę życzeń",
            ["panel.tooltip.assignment_heading"] = "Przypisz listę życzeń",
            ["panel.tooltip.assignment_chooser"] = "Otwiera Echo Journal z wyborem listy życzeń dla tego zestawu. Nic nie zostanie przypisane, dopóki nie wybierzesz tam listy życzeń.",
            ["panel.button.create_wishlist"] = "Utwórz listę życzeń",
            ["panel.tooltip.create_wishlist_heading"] = "Zaimportuj lub utwórz listę życzeń",
            ["panel.tooltip.create_wishlist_source"] = "Wklej ciąg listy życzeń lub zbuduj ją bezpośrednio w Nexus.",
            ["panel.tooltip.create_wishlist_draft"] = "To otwiera edytor listy życzeń z wersją roboczą. Nic nie zostanie zapisane ani przypisane, dopóki nie naciśniesz tam Create & assign lub Create unassigned.",
            ["panel.heading.locked_targets"] = "ZABLOKOWANE CELE",
            ["panel.tooltip.locked_remaining"] = "Pozostałe zablokowane cele",
            ["panel.tooltip.locked_plan"] = "Te cele są zaplanowane dla twoich zablokowanych miejsc Echo (plan przewiduje najwyżej sześć kopii docelowych).",
            ["panel.tooltip.locked_acquire"] = "Najpierw zdobądź dokładnie żądane Echo w dokładnie żądanej jakości.",
            ["panel.tooltip.locked_placement"] = "Posiadane kopie trzeba jeszcze umieścić w zablokowanych miejscach Echo.",
            ["panel.tooltip.locked_not_freeze"] = "Obecne zablokowane miejsca Echo i Freeze kart to osobne rzeczy.",
            ["panel.tooltip.locked_acquire_list"] = "Nadal do zdobycia:",
            ["panel.tooltip.open_wishlist_editor"] = "Kliknij, aby otworzyć edytor listy życzeń",
            ["panel.heading.progress"] = "POSTĘP",
            ["panel.heading.still_needed"] = "NADAL POTRZEBNE",
            ["panel.heading.extra_copies"] = "DODATKOWE KOPIE",
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
            ["panel.button.my_builds"] = "Meus builds",
            ["panel.tooltip.open_my_builds"] = "Abrir My Builds",
            ["panel.tooltip.my_builds_destination"] = "Abre a página My Builds do servidor. Escolher lá outro Saved Build muda a configuração ativa.",
            ["panel.button.assign_wishlist"] = "Atribuir lista de desejos",
            ["panel.tooltip.assignment_heading"] = "Atribuir lista de desejos",
            ["panel.tooltip.assignment_chooser"] = "Abre o Echo Journal com o seletor de lista de desejos desta configuração. Nada é atribuído até você escolher uma lista de desejos lá.",
            ["panel.button.create_wishlist"] = "Criar lista de desejos",
            ["panel.tooltip.create_wishlist_heading"] = "Importar ou criar uma lista de desejos",
            ["panel.tooltip.create_wishlist_source"] = "Cole um texto de lista de desejos ou monte uma diretamente no Nexus.",
            ["panel.tooltip.create_wishlist_draft"] = "Isto abre o editor de listas de desejos com um rascunho. Nada é salvo ou atribuído até você pressionar Create & assign ou Create unassigned lá.",
            ["panel.heading.locked_targets"] = "ALVOS BLOQUEADOS",
            ["panel.tooltip.locked_remaining"] = "Alvos bloqueados restantes",
            ["panel.tooltip.locked_plan"] = "Estes alvos estão planejados para seus espaços de Echo bloqueados (um plano prevê no máximo seis cópias de alvo).",
            ["panel.tooltip.locked_acquire"] = "Obtenha primeiro exatamente o Echo e a qualidade solicitados.",
            ["panel.tooltip.locked_placement"] = "Cópias possuídas ainda precisam ser colocadas em espaços de Echo bloqueados.",
            ["panel.tooltip.locked_not_freeze"] = "Os espaços de Echo bloqueados atuais e o Freeze de cartas são coisas separadas.",
            ["panel.tooltip.locked_acquire_list"] = "Ainda falta obter:",
            ["panel.tooltip.open_wishlist_editor"] = "Clique para abrir o editor de listas de desejos",
            ["panel.heading.progress"] = "PROGRESSO",
            ["panel.heading.still_needed"] = "AINDA NECESSÁRIO",
            ["panel.heading.extra_copies"] = "CÓPIAS EXTRAS",
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
            ["panel.button.my_builds"] = "Мои сборки",
            ["panel.tooltip.open_my_builds"] = "Открыть My Builds",
            ["panel.tooltip.my_builds_destination"] = "Открывает страницу сервера My Builds. Выбор там другого Saved Build меняет активный набор.",
            ["panel.button.assign_wishlist"] = "Назначить список желаний",
            ["panel.tooltip.assignment_heading"] = "Назначить список желаний",
            ["panel.tooltip.assignment_chooser"] = "Открывает Echo Journal с выбором списка желаний для этого набора. Ничего не назначается, пока вы не выберете там список желаний.",
            ["panel.button.create_wishlist"] = "Создать список желаний",
            ["panel.tooltip.create_wishlist_heading"] = "Импортировать или создать список желаний",
            ["panel.tooltip.create_wishlist_source"] = "Вставьте строку списка желаний или создайте его прямо в Nexus.",
            ["panel.tooltip.create_wishlist_draft"] = "Открывает редактор списка желаний с черновиком. Ничего не сохраняется и не назначается, пока вы не нажмёте там Create & assign или Create unassigned.",
            ["panel.heading.locked_targets"] = "ЗАКРЕПЛЁННЫЕ ЦЕЛИ",
            ["panel.tooltip.locked_remaining"] = "Оставшиеся закреплённые цели",
            ["panel.tooltip.locked_plan"] = "Эти цели запланированы для ваших закреплённых слотов Echo (план предусматривает не более шести копий целей).",
            ["panel.tooltip.locked_acquire"] = "Сначала получите точно запрошенный Echo в точно запрошенном качестве.",
            ["panel.tooltip.locked_placement"] = "Имеющиеся копии ещё нужно поместить в закреплённые слоты Echo.",
            ["panel.tooltip.locked_not_freeze"] = "Текущие закреплённые слоты Echo и Freeze карт — разные вещи.",
            ["panel.tooltip.locked_acquire_list"] = "Ещё нужно получить:",
            ["panel.tooltip.open_wishlist_editor"] = "Нажмите, чтобы открыть редактор списка желаний",
            ["panel.heading.progress"] = "ПРОГРЕСС",
            ["panel.heading.still_needed"] = "ЕЩЁ НУЖНО",
            ["panel.heading.extra_copies"] = "ЛИШНИЕ КОПИИ",
        },
    },
}
