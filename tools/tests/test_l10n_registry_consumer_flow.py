"""Registry-bound localization catalog, S8 part 2: the value-flow, receiver,
environment, wrapper and dispatch rule controls C20-C38 of consumer_binding_report (Refs #147).

Split from the single registry test file (SPLIT-PLAN.md): its classes are copied
verbatim; shared names come from tools/tests/l10n_registry_support.py. Synthetic offline
evidence only: no Lua runs, and this is not fluent, human or native evidence. Python 3.9+,
standard library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_registry_consumer_flow.py -v
"""

import importlib.util
import sys
import unittest
from pathlib import Path


def _registry_support():
    """tools/tests/l10n_registry_support.py, loaded once per process from its file path without
    writing bytecode (as load_catalog loads the tool), whatever the working directory."""
    name = "l10n_registry_support"
    if name not in sys.modules:
        previous = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            spec = importlib.util.spec_from_file_location(
                name, Path(__file__).resolve().with_name(name + ".py"))
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            try:
                spec.loader.exec_module(module)
            except BaseException:
                del sys.modules[name]
                raise
        finally:
            sys.dont_write_bytecode = previous
    return sys.modules[name]


# Every name the original single test module defined outside its test classes (imports,
# constants, helpers, the shared tool and file memos, tearDownModule), bound here to the same
# objects, so these classes see the namespace they saw there.
globals().update({name: value for name, value in vars(_registry_support()).items()
                  if not name.startswith("__")})


# Part 2 of 2 of the original ConsumerBindingTests (C20-C38, 20 tests). The other part is
# in test_l10n_registry_consumers.py (C0-C19). Its setUpClass and helper
# methods are _ConsumerBindingMixin of l10n_registry_support.py, verbatim.
class ConsumerBindingTests(_ConsumerBindingMixin, unittest.TestCase):
    """S8: the registered current-repository static consumer binding gate
    and its negative controls on in-memory edits of the real bytes."""

    def test_c20_table_write_and_receiver_origins_follow_the_actual_object(self):
        # Review fix 3 (SPEC-147-S8-RF2-1..3): a table written through a
        # parameter is the one the value's own call passed; a receiver field
        # is bound to the object holding it; a widget factory and a client
        # global need an evidenced client root.
        key, host = "panel.heading.progress", "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        store = b'local function SpecStore(target,value) target.SpecUniqueField=value end; '
        show = b'local function SpecShow(target,value) target:SetText(value) end; '
        cases = (
            ("same-call table write", True, store + b'local specLeft={}; SpecStore(specLeft,'
             + text + b'); specLabel:SetText(specLeft.SpecUniqueField)'),
            ("separate-call table write", False, store + b'local specLeft={}; local specRight={}; '
             b'SpecStore(specLeft,' + text + b'); SpecStore(specRight,"fixed"); '
             b'specLabel:SetText(specRight.SpecUniqueField)'),
            ("same-object widget field", True, b'local specLeft={_SpecUniqueOutput=UIParent:'
             b'CreateFontString()}; specLeft._SpecUniqueOutput:SetText(' + text + b')'),
            ("unrelated-object widget field", False, b'local specLeft={_SpecUniqueOutput=UIParent:'
             b'CreateFontString()}; local specRight={}; specRight._SpecUniqueOutput:SetText('
             + text + b')'),
            ("factory on an empty table", False, b'local specMaker={}; local specMade=specMaker:'
             b'CreateFontString(); specMade:SetText(' + text + b')'),
            ("unknown global receiver", False,
             b'SpecUnknownNotAClientFrame:SetText(' + text + b')'),
            ("widget passed to every call", True, show + b'SpecShow(specLabel,' + text + b')'),
            ("value shown by the call passing the widget", True, show + b'SpecShow(specLabel,'
             + text + b'); SpecShow({SetText=function() end},"fixed")'),
            ("value given to the call passing a fake table", False, show
             + b'SpecShow({SetText=function() end},' + text + b'); SpecShow(specLabel,"fixed")'),
            # A value made inside the function reaches the receiver of every
            # call, so every call must pass a client object.
            ("own value shown on a widget passed by every call", True,
             b'local function SpecOwn(target) target:SetText(' + text + b') end; '
             b'SpecOwn(specLabel)'),
            ("own value shown on a fake table passed by a call", False,
             b'local function SpecOwn(target) target:SetText(' + text + b') end; '
             b'SpecOwn(specLabel); SpecOwn({SetText=function() end})'),
        )
        for name, binds, code in cases:
            with self.subTest(case=name):
                receipt = self.receipt(with_file(bare, host, self.files[host] + label + code
                                                 + b'\n'))
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"])

    def test_c21_reads_receiver_fields_methods_and_nil_follow_the_actual_origin(self):
        # Review fix 4 (SPEC-147-S8-RF3-1..4): a field read through a
        # parameter returns only to the call that passed the read table; a
        # receiver field through a parameter is resolved on that call's
        # table; a replaced output method is no output; and a later nil
        # assignment is a definition of the receiver.
        key, host = "panel.heading.progress", "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        read = b'local function SpecRead(target) return target.SpecReadField end; '
        show = b'local function SpecShow(target,value) target.SpecOutput:SetText(value) end; '
        cases = (
            ("same-call field read", True, read + b'local specLeft={SpecReadField=' + text
             + b'}; specLabel:SetText(SpecRead(specLeft))'),
            ("separate-call field read", False, read + b'local specLeft={SpecReadField=' + text
             + b'}; local specRight={}; local specDiscard=SpecRead(specLeft); '
             b'specLabel:SetText(SpecRead(specRight))'),
            ("separate-call field read through a parameter alias", False,
             b'local function SpecRead(target) local held=target; return held.SpecReadField end; '
             b'local specLeft={SpecReadField=' + text + b'}; local specRight={}; '
             b'local specDiscard=SpecRead(specLeft); specLabel:SetText(SpecRead(specRight))'),
            ("same-object parameter receiver field", True, show
             + b'local specLeft={SpecOutput=specLabel}; SpecShow(specLeft,' + text + b')'),
            ("other-call parameter receiver field", False, show
             + b'local specLeft={SpecOutput=specLabel}; local specRight={}; '
             b'SpecShow(specLeft,"fixed"); SpecShow(specRight,' + text + b')'),
            ("output method replaced on the widget", False,
             b'specLabel.SetText=function(self,value) return nil end; specLabel:SetText(' + text
             + b')'),
            ("output method replaced through a widget alias", False,
             b'local specSame=specLabel; specSame.SetText=function(self,value) end; '
             b'specLabel:SetText(' + text + b')'),
            ("unmodified widget method", True, b'specLabel:SetText(' + text + b')'),
            ("initial nil then created", True, b'local specMaybe=nil; specMaybe=UIParent:'
             b'CreateFontString(); specMaybe:SetText(' + text + b')'),
            ("created then nil", False, b'specLabel=nil; specLabel:SetText(' + text + b')'),
        )
        for name, binds, code in cases:
            with self.subTest(case=name):
                receipt = self.receipt(with_file(bare, host, self.files[host] + label + code
                                                 + b'\n'))
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"])

    def test_c22_nested_calls_keep_every_enclosing_invocation(self):
        # SPEC-147-S8-RF4-1: a field read through a parameter that a wrapper
        # passes on from its own parameter returns only under the enclosing
        # call whose argument holds the written table, so the wrapper's
        # result reaches only that call. A resolved helper that receives the
        # widget leaves it an output unless it replaces the output method.
        key, host = "panel.heading.progress", "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        read = b'local function SpecRead(target) return target.SpecReadField end; '
        wrap = read + b'local function SpecWrap(target) return SpecRead(target) end; '
        outer = wrap + b'local function SpecOuter(target) return SpecWrap(target) end; '
        left = b'local specLeft={SpecReadField=' + text + b'}; local specRight={}; '
        fill = read + (b'local function SpecFill(target,value) target.SpecReadField=value; '
                       b'return SpecRead(target) end; ')
        cases = (
            ("nested-field-read-same-call-positive", True, wrap + b'local specLeft={SpecReadField='
             + text + b'}; specLabel:SetText(SpecWrap(specLeft))'),
            ("nested-field-read-wrong-call-origin", False, wrap + left
             + b'local specDiscard=SpecWrap(specLeft); specLabel:SetText(SpecWrap(specRight))'),
            ("nested read through an alias of the wrapper parameter", False, read
             + b'local function SpecWrap(target) local held=target; return SpecRead(held) end; '
             + left + b'local specDiscard=SpecWrap(specLeft); '
             b'specLabel:SetText(SpecWrap(specRight))'),
            ("two enclosing wrappers, same call", True, outer + left
             + b'specLabel:SetText(SpecOuter(specLeft))'),
            ("two enclosing wrappers, wrong call", False, outer + left
             + b'local specDiscard=SpecOuter(specLeft); specLabel:SetText(SpecOuter(specRight))'),
            ("table written and read in one enclosing call", True, fill
             + b'specLabel:SetText(SpecFill({},' + text + b')); local specOther=SpecFill({},"x")'),
            ("table written and read in a discarded enclosing call", False, fill
             + b'local specDiscard=SpecFill({},' + text + b'); '
             b'specLabel:SetText(SpecFill({},"fixed"))'),
            ("method-helper-unmodified-positive", True,
             b'local function SpecTouch(target) local same=target end; SpecTouch(specLabel); '
             b'specLabel:SetText(' + text + b')'),
            ("method-helper-overwrite-origin", False,
             b'local function SpecTouch(target) target.SetText=function(self,value) return nil '
             b'end end; SpecTouch(specLabel); specLabel:SetText(' + text + b')'),
        )
        for name, binds, code in cases:
            with self.subTest(case=name):
                receipt = self.receipt(with_file(bare, host, self.files[host] + label + code
                                                 + b'\n'))
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"])

    def test_c23_a_carrier_made_in_a_call_belongs_to_that_call(self):
        # SPEC-147-S8-RF5-1: a table made inside a function is a fresh object
        # in each of its invocations, so a field written and read on it, read
        # directly or passed on, stays with the invocation that wrote it.
        key, host = "panel.heading.progress", "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        read = b'local function SpecRead(target) return target.SpecBridge end; '
        left = b'local specLeft={SpecSource=' + text + b'}; local specRight={}; '
        shown = b'specLabel:SetText(SpecWrap(specLeft))'
        wrong = b'local specDiscard=SpecWrap(specLeft); specLabel:SetText(SpecWrap(specRight))'
        wraps = (
            ("constructor carrier", read + b'local function SpecWrap(target) local box='
             b'{SpecBridge=target.SpecSource}; return SpecRead(box) end; '),
            ("assigned carrier", read + b'local function SpecWrap(target) local box={}; '
             b'box.SpecBridge=target.SpecSource; return SpecRead(box) end; '),
            ("carrier read in place", b'local function SpecWrap(target) local box='
             b'{SpecBridge=target.SpecSource}; return box.SpecBridge end; '),
            ("carrier passed as a constructor", read + b'local function SpecWrap(target) '
             b'return SpecRead({SpecBridge=target.SpecSource}) end; '),
        )
        cases = [(name + ", same call", True, wrap + left + shown) for name, wrap in wraps]
        cases += [(name + ", wrong call", False, wrap + left + wrong) for name, wrap in wraps]
        # A carrier made in a nested function whose invocation the value's
        # call stack does not hold stays unproven.
        cases.append(("carrier made in a nested function, wrong call", False, read
                      + b'local function SpecWrap(target) local function SpecInner() local box='
                      b'{SpecBridge=target.SpecSource}; return SpecRead(box) end; '
                      b'return SpecInner() end; ' + left + wrong))
        # A value made inside the function reaches the carrier of every call.
        cases.append(("own value through a carrier", True, read + b'local function SpecMake() '
                      b'local box={SpecBridge=' + text + b'}; return SpecRead(box) end; '
                      b'specLabel:SetText(SpecMake())'))
        for name, binds, code in cases:
            with self.subTest(case=name):
                receipt = self.receipt(with_file(bare, host, self.files[host] + label + code
                                                 + b'\n'))
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"])

    def test_c24_a_field_copied_into_the_same_field_name_still_binds(self):
        # SPEC-147-S8-RF6-1: every write of a field name must carry the proof,
        # and a carrier copy of the same field name is itself such a write, fed
        # only by the field it copies; that dependency cycle must not refuse a
        # genuine same-call display, while a copy from a table that never holds
        # the value, or a discarded call, still proves nothing.
        key, host = "panel.heading.progress", "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        direct = b'local function SpecRead(target) return target.SpecShared end; '
        alias = b'local function SpecRead(target) local same=target; return same.SpecShared end; '
        built = (b'local function SpecWrap(target) local box={SpecShared=target.SpecShared}; '
                 b'return SpecRead(box) end; ')
        assigned = (b'local function SpecWrap(target) local box={}; '
                    b'box.SpecShared=target.SpecShared; return SpecRead(box) end; ')
        left = b'local specLeft={SpecShared=' + text + b'}; local specRight={}; '
        shown = b'specLabel:SetText(SpecWrap(specLeft))'
        wrong = b'local specDiscard=SpecWrap(specLeft); specLabel:SetText(SpecWrap(specRight))'
        forms = (("constructor carrier", direct + built), ("constructor carrier, reader alias",
                                                          alias + built),
                 ("assigned carrier", direct + assigned), ("assigned carrier, reader alias",
                                                           alias + assigned))
        cases = [(name + ", same call", True, code + left + shown) for name, code in forms]
        cases += [(name + ", wrong call", False, code + left + wrong) for name, code in forms]
        cases += [
            ("aliased reader without a carrier", True, alias + left
             + b'specLabel:SetText(SpecRead(specLeft))'),
            ("carrier with another field name", True, b'local function SpecRead(target) return '
             b'target.SpecBridge end; local function SpecWrap(target) local box={SpecBridge='
             b'target.SpecShared}; return SpecRead(box) end; ' + left + shown),
            # The same field copied from a table that never holds the value
            # replaces it; no other write makes that copy carry the proof.
            ("field overwritten by the same field of an empty table", False, left
             + b'specLeft.SpecShared=specRight.SpecShared; specLabel:SetText(specLeft.SpecShared)'),
            # A write is assumed to pass only while all its definitions are
            # reached: one copying that overwritten field proves nothing either.
            ("field copied from a field overwritten by an empty table", False, left
             + b'specLeft.SpecShared=specRight.SpecShared; local specOther={SpecCopy=' + text
             + b'}; specOther.SpecCopy=specLeft.SpecShared; specLabel:SetText(specOther.SpecCopy)'),
        ]
        for name, binds, code in cases:
            with self.subTest(case=name):
                receipt = self.receipt(with_file(bare, host, self.files[host] + label + code
                                                 + b'\n'))
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                # Every localization call of the case is an unproven site.
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"] * code.count(text))

    def test_c25_a_field_copied_through_two_fresh_carriers_still_binds(self):
        # SPEC-147-S8-RF7-1: a field copied through two fresh carrier tables,
        # each written once, binds for the call that displays it; a field
        # written back from its own copy after an empty table overwrote it
        # (the order of those writes is unknown) proves nothing, whether the
        # copy keeps the field name or crosses to another one.
        key, host = "panel.heading.progress", "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        direct = b'local function SpecRead(target) return target.SpecShared end; '
        alias = b'local function SpecRead(target) local same=target; return same.SpecShared end; '
        built = (b'local function SpecWrap(target) local first={SpecShared=target.SpecShared}; '
                 b'local box={SpecShared=first.SpecShared}; return SpecRead(box) end; ')
        assigned = (b'local function SpecWrap(target) local first={}; '
                    b'first.SpecShared=target.SpecShared; local box={}; '
                    b'box.SpecShared=first.SpecShared; return SpecRead(box) end; ')
        left = b'local specLeft={SpecShared=' + text + b'}; local specRight={}; '
        shown = b'specLabel:SetText(SpecWrap(specLeft))'
        wrong = b'local specDiscard=SpecWrap(specLeft); specLabel:SetText(SpecWrap(specRight))'
        forms = (("two constructor carriers", direct + built),
                 ("two constructor carriers, reader alias", alias + built),
                 ("two assigned carriers", direct + assigned))
        cases = [(name + ", same call", True, code + left + shown) for name, code in forms]
        cases += [(name + ", wrong call", False, code + left + wrong) for name, code in forms]
        cases += [
            ("two carriers in the chunk", True, left + b'local first={SpecShared=specLeft.SpecShared}; '
             b'local box={SpecShared=first.SpecShared}; specLabel:SetText(box.SpecShared)'),
            ("one carrier in the chunk", True, left + b'local box={SpecShared=specLeft.SpecShared}; '
             b'specLabel:SetText(box.SpecShared)'),
            ("two carriers, the first with another field name", True, direct
             + b'local function SpecWrap(target) local first={SpecBridge=target.SpecShared}; '
             b'local box={SpecShared=first.SpecBridge}; return SpecRead(box) end; ' + left + shown),
            ("round trip after an empty overwrite", False, left + b'specLeft.SpecShared='
             b'specRight.SpecShared; specRight.SpecShared=specLeft.SpecShared; '
             b'specLabel:SetText(specLeft.SpecShared)'),
            ("round trip after an empty overwrite, copy shown", False, left
             + b'specLeft.SpecShared=specRight.SpecShared; specRight.SpecShared='
             b'specLeft.SpecShared; specLabel:SetText(specRight.SpecShared)'),
            ("cross-field round trip after an empty overwrite", False, b'local specLeft={SpecA='
             + text + b'}; local specRight={}; specLeft.SpecA=specRight.SpecB; '
             b'specRight.SpecB=specLeft.SpecA; specLabel:SetText(specRight.SpecB)'),
        ]
        for name, binds, code in cases:
            with self.subTest(case=name):
                receipt = self.receipt(with_file(bare, host, self.files[host] + label + code
                                                 + b'\n'))
                if binds:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual([(problem["code"], problem.get("key"))
                                  for problem in receipt["problems"]], [("binding-unbound", key)])
                self.assertEqual([site["reason"] for site
                                  in self.binding(receipt, key)["unprovenSites"]],
                                 ["output-not-reached"] * code.count(text))

    def test_c26_v15_rules_bind_only_their_proved_forms(self):
        # V15 binder rules, each with its refusal on the real bytes: the
        # lazy-field metatable statement (charge row, ui/Readout.lua), the
        # pairs-iterated guard (mapped reasons), reaching definitions, text
        # transforms and helper receivers (progress heading, on the host
        # substrate of c20..c25: the real Panel shows only the literal and
        # the case code follows core/SessionPause.lua). Every refusal is the
        # gate's own binding-unbound of exactly the keys the edit takes away.
        progress = "panel.heading.progress"
        hook = b'setmetatable(M, {__index = function(_, name)\n    local entry = SHOWN[name]'
        self.assertEqual(self.files[READOUT].replace(b"\r\n", b"\n").count(hook), 1)
        readout = (
            # (name, edited hook, keys left UNBOUND)
            ("hook with a named unused table parameter",
             hook.replace(b"function(_, name)", b"function(t, name)"), ()),
            ("hook also holding __newindex", hook.replace(b"{__index", b"{__newindex = rawset, __index"),
             (CHARGE,)),
            ("hook using its table parameter",
             hook.replace(b"function(_, name)", b"function(t, name)") + b" or rawget(t, name)",
             (CHARGE,)),
            # core/UserText.lua hooks its module the same way, so the mapped
            # reasons lose their chain too.
            ("setmetatable assigned in the loaded source", b"setmetatable = setmetatable\n" + hook,
             (CHARGE,) + MAPPED_KEYS),
        )
        host = "core/SessionPause.lua"
        bare = with_file(self.files, PANEL, edit(self.files[PANEL], PROGRESS_CALL,
                                                 b'progressLabel:SetText("Progress")'))
        label = b'\nlocal specLabel = UIParent:CreateFontString(nil, "OVERLAY")\n'
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        local = b'do local s = ' + text + b'; '
        hosted = (
            # (name, code after the label, keys left UNBOUND)
            ("the label shown directly", b'specLabel:SetText(' + text + b')', ()),
            ("pairs assigned in the loaded source", b'specLabel:SetText(' + text + b') pairs = pairs',
             MAPPED_KEYS),
            ("a branch alternative still reaches the output",
             local + b'if specLabel.x then s = "x" end; specLabel:SetText(s) end', ()),
            ("a later definition reaches the output", b'local function f() local s = "x"; s = '
             + text + b'; specLabel:SetText(s) end f()', ()),
            ("a sequential overwrite reaches it instead",
             local + b's = "x"; specLabel:SetText(s) end', (progress,)),
            ("a sequential overwrite inside a function", b'local function f() local s = ' + text
             + b'; s = "x"; specLabel:SetText(s) end f()', (progress,)),
            ("a method transform", b'specLabel:SetText(' + text + b':upper())', ()),
            ("a library transform", b'specLabel:SetText(string.upper(tostring(' + text + b')))', ()),
            ("tostring assigned in the loaded source",
             b'specLabel:SetText(tostring(' + text + b')) tostring = tostring', (progress,)),
            ("string assigned in the loaded source",
             b'specLabel:SetText(string.upper(' + text + b')) string = string', (progress,)),
            ("a helper returning the client label",
             b'local function lbl() return specLabel end lbl():SetText(' + text + b')', ()),
            ("a helper returning a stand-in table",
             b'local function lbl() return {SetText = print} end lbl():SetText(' + text + b')',
             (progress,)),
            ("a helper with one stand-in return", b'local function lbl(x) if x then return specLabel'
             b' end return {SetText = print} end lbl():SetText(' + text + b')', (progress,)),
        )
        cases = [(name, with_file(self.files, READOUT, edit(self.files[READOUT], hook, new)), unbound)
                 for name, new, unbound in readout]
        cases += [(name, with_file(bare, host, self.files[host] + label + code + b'\n'), unbound)
                  for name, code, unbound in hosted]
        for name, files, unbound in cases:
            with self.subTest(case=name):
                receipt = self.receipt(files)
                if not unbound:
                    assert_binding_receipt(self, receipt)
                    continue
                with self.assertRaises(AssertionError):
                    assert_binding_receipt(self, receipt)
                self.assertEqual(sorted(row["key"] for row in receipt["keys"]
                                        if row["binding"] == "UNBOUND"), sorted(unbound))
                self.assertEqual(sorted(problem.get("key") for problem
                                        in self.problems(receipt, "binding-unbound")),
                                 sorted(unbound))

    def test_c27_environment_and_library_writes_refuse_trusted_globals(self):
        # V15 review fix (SPEC-V15-1 _G.pairs and _G.setmetatable, STD-V15-2):
        # a trusted global or string library function replaced through _G, a
        # library field, a static or computed key, an alias, rawset or the
        # string metatable is no longer trusted, whatever the order of the
        # write and the use; a reference that may write any global is a
        # global-environment mutation problem. Reads, tests and other
        # globals leave each proof in place.
        progress = "panel.heading.progress"
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        upper = b'specLabel:SetText(string.upper(' + text + b'))'
        method = b'specLabel:SetText(' + text + b':upper())'
        fixed = b'function(_) return "fixed" end '
        hosted = (
            # (name, code after the label, keys left UNBOUND)
            # The Spec witnesses' replacements (made in core/UserText.lua
            # there; a global is one for every loaded file): the dispatcher's
            # pairs-iterated guard, and the metatable statement of its module
            # and of ui/Readout.lua's (the charge row's chain).
            ("pairs replaced through _G", method + b' _G.pairs = function(t) '
             b't.STORE_PENDING = "shadowed" return next, t, nil end', MAPPED_KEYS),
            ("setmetatable replaced through _G", method + b' _G.setmetatable = function(t, meta) '
             b't.Message = function(value) return "constant" end return t end',
             (CHARGE,) + MAPPED_KEYS),
            ("string.upper replaced, library call", b'string.upper = ' + fixed + upper,
             (progress,)),
            ("string.upper replaced, method call", b'string.upper = ' + fixed + method,
             (progress,)),
            ("replaced after the use", method + b' string.upper = ' + fixed, (progress,)),
            ("replaced through _G.string", b'_G.string.upper = ' + fixed + method, (progress,)),
            ("replaced under a static key", b'string["up" .. "per"] = ' + fixed + upper,
             (progress,)),
            ("replaced through a local alias",
             b'local s = string; s.upper = ' + fixed + upper, (progress,)),
            ("replaced under a computed key",
             b'for k in pairs({}) do string[k] = nil end ' + method, (progress,)),
            ("replaced by rawset", b'rawset(string, "upper", ' + fixed[:-1] + b') ' + upper,
             (progress,)),
            ("the string metatable reached", b'getmetatable("").__index.upper = ' + fixed + method,
             (progress,)),
            ("__tostring through the string metatable",
             b'getmetatable("").__tostring = ' + fixed + b'specLabel:SetText(tostring('
             + text + b'))', (progress,)),
            ("tostring replaced through _G", b'_G.tostring = ' + fixed
             + b'specLabel:SetText(tostring(' + text + b'))', (progress,)),
            ("format replaced, method call", b'string.format = ' + fixed
             + b'specLabel:SetText(("%s"):format(' + text + b'))', (progress,)),
        )
        for name, code, unbound in hosted:
            with self.subTest(case=name):
                self.assert_unbound_exactly(self.receipt(self.hosted(code)), unbound)
        # Reads, tests, comparisons and other globals keep every proof: one
        # receipt (they write no trusted global), each site judged alone.
        self.per_site((
            ("a library field read", upper + b' local up = string.upper', True),
            ("a tested getmetatable result",
             b'if getmetatable(specLabel) == nil then end ' + method, True),
            ("_G and debug only tested", b'if _G and type(debug) == "table" and _G.UIParent '
             b'then end ' + method, True),
            ("another global written through _G",
             b'_G.NexusSpecValue = 1 local f = _G["GameFont" .. "Normal"] ' + method, True),
            # STD-8849-2: a computed _G[k] read keeps a proof only when its
            # key is proved to name no trusted global, or the global it reads
            # is only tested, field-tested or called as a method.
            ("a read-only literal list of names", b'local names = {"NexusSpecA", "NexusSpecB"} '
             b'for i = 1, #names do local f = _G[names[i]] if f and f.Hide then pcall(f.Hide, f) '
             b'end end ' + method, True),
            ("a loop over literal suffixes", b'for _, part in ipairs({"Low", "High"}) do '
             b'local f = _G[specLabel:GetName() .. part] if f then f:Hide() end end ' + method,
             True),
            ("an unknown global only tested and called as a method",
             b'local f = _G[specLabel:GetName()] if f and f.IsShown and f:IsShown() then end '
             + method, True)))
        # A reference that may write any global: no global stays trusted,
        # so no output is proved, and the reference is a mutation problem.
        for name, code in (("_G aliased", b'local G = _G; G.pairs = pairs'),
                           ("a computed _G write", b'for k in pairs({}) do _G[k] = nil end'),
                           ("_G passed to rawset", b'rawset(_G, "pairs", pairs)'),
                           ("an environment function", b'setfenv(1, {})'),
                           # STD-8849-2: the reviewer's computed reads of the
                           # string library, and an unknown global passed on
                           # or called through a method the source defines.
                           ("a computed _G read written through",
                            b'local key = tostring("string"); _G[key].upper = function(_) '
                            b'return "fixed" end'),
                           ("a computed _G call key written through",
                            b'_G[tostring("string")].upper = function(_) return "fixed" end'),
                           ("an unknown global passed on",
                            b'local f = _G[specLabel:GetName()] Nexus.Readout.ChargesLine(f)'),
                           ("an unknown global's method defined here",
                            b'function specLabel.Grab(self) end local f = _G[specLabel:GetName()] '
                            b'if f then f:Grab() end')):
            with self.subTest(case=name):
                receipt = self.receipt(self.hosted(method + b' ' + code))
                self.assertEqual([(problem["path"], problem["construct"]) for problem
                                  in self.problems(receipt, "binding-mutation")],
                                 [("core/SessionPause.lua", "global-environment")])
                self.assertEqual([row["binding"] for row in receipt["keys"]],
                                 ["UNBOUND"] * len(CURRENT_KEYS))

    def test_c27_rawget_of_an_ordinary_global_is_one_read_while_rawget_is_the_builtin(self):
        # Registry rawget repair (current repository, core/GameAdapter.lua:
        # rawget(_G, "NexusDB"), a metamethod-free read of the saved data).
        # rawget(_G, key) is the read of one ordinary global, like _G.key,
        # only in this exact form: the global name rawget, the global name _G
        # and a static key that names no tracked global, and only while no
        # loaded source assigns rawget. Every other form still opens the
        # environment at its own reference. The expected positions below are
        # computed from the appended bytes, never read from the tool.
        progress = "panel.heading.progress"
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        method = b'specLabel:SetText(' + text + b':upper())'
        host, other = "core/SessionPause.lua", "core/WishlistController.lua"
        read = b'local saved = rawget(_G, "NexusDB")'
        first = (self.files[host] + V15_LABEL).count(b"\n") + 1
        self.assertIn(other, self.files)
        self.assertNotEqual(host, other)

        # 1. The safe read keeps the whole gate: no mutation problem, every
        # dated key bound, and the progress heading bound by the hosted site.
        with self.subTest(case="the safe read keeps the whole gate"):
            receipt = self.receipt(self.hosted(read + b' ' + method))
            self.assertEqual(self.problems(receipt, "binding-mutation"), [])
            assert_binding_receipt(self, receipt)
            row = self.binding(receipt, progress)
            self.assertEqual({site["path"] for site in row["sites"] if site["outputs"]}, {host})
            self.assertEqual([site["line"] for site in row["sites"] if site["outputs"]], [first])
        # Its other safe shapes, each judged by its own site in one receipt.
        self.per_site((
            ("a static key", read + b' ' + method, True),
            ("a concatenated static key",
             b'local saved = rawget(_G, "Nexus" .. "DB") ' + method, True),
            ("an unassigned local static key",
             b'local name = "NexusDB" local saved = rawget(_G, name) ' + method, True),
            ("the value read on with rawget inside a function",
             b'local function mark() local root = rawget(_G, "NexusDB") '
             b'return type(root) == "table" and rawget(root, "chars") or nil end mark() '
             + method, True)))

        # 2. Every other form refuses for its own reason: one mutation problem
        # at the reference that opens the environment, and nothing bound.
        # (name, code after the bound call, bytes that locate the reference,
        # offset of the reference in them)
        opened = (
            ("a local named rawget",
             b'local rawget = function(t, k) return t end local e = rawget(_G, "NexusDB")',
             b'rawget(_G', 7),
            ("a parameter named rawget",
             b'local function f(rawget) return rawget(_G, "NexusDB") end', b'rawget(_G', 7),
            ("a local alias of rawget",
             b'local get = rawget local e = get(_G, "NexusDB")', b'get(_G', 4),
            ("rawget assigned before the read",
             b'rawget = function(t, k) return t end local e = rawget(_G, "NexusDB")',
             b'rawget(_G', 7),
            ("rawget assigned after the read",
             b'local e = rawget(_G, "NexusDB") rawget = function(t, k) return t end',
             b'rawget(_G', 7),
            ("rawget defined as a global function",
             b'function rawget(t, k) return t end local e = rawget(_G, "NexusDB")',
             b'rawget(_G', 7),
            ("rawget replaced through _G",
             b'_G.rawget = function(t, k) return t end local e = rawget(_G, "NexusDB")',
             b'rawget(_G', 7),
            ("rawget replaced under a static _G key",
             b'_G["raw" .. "get"] = function(t, k) return t end local e = rawget(_G, "NexusDB")',
             b'rawget(_G', 7),
            ("the environment itself read",
             b'local e = rawget(_G, "_G") e.pairs = pairs', b'rawget(_G', 7),
            ("an environment opener read", b'local f = rawget(_G, "setfenv")', b'rawget(_G', 7),
            ("the Nexus root read", b'local n = rawget(_G, "Nexus")', b'rawget(_G', 7),
            ("the string library read", b'local s = rawget(_G, "string")', b'rawget(_G', 7),
            ("a trusted function read", b'local p = rawget(_G, "pairs")', b'rawget(_G', 7),
            ("an unknown key", b'local e = rawget(_G, specLabel:GetName())', b'rawget(_G', 7),
            ("a reassigned local key",
             b'local name = "NexusDB" name = "_G" local e = rawget(_G, name)', b'rawget(_G', 7),
            ("no key", b'local e = rawget(_G)', b'rawget(_G', 7),
            ("the environment through an alias",
             b'local G = _G local e = rawget(G, "NexusDB")', b'= _G', 2),
            # A real mutation beside the safe read is reported at the mutation,
            # not at the read.
            ("the environment written beside a safe read",
             read + b' rawset(_G, "pairs", pairs)', b'rawset(_G', 7),
            ("an environment function beside a safe read",
             read + b' setfenv(1, {})', b'setfenv', 0),
        )
        for name, code, needle, offset in opened:
            with self.subTest(case=name):
                line = method + b' ' + code
                self.assertEqual(line.count(needle), 1)
                column = line.index(needle) + offset + 1
                receipt = self.receipt(self.hosted(line))
                self.assertEqual([(problem["path"], problem["construct"], problem["line"],
                                   problem["column"]) for problem
                                  in self.problems(receipt, "binding-mutation")],
                                 [(host, "global-environment", first, column)])
                self.assertEqual([row["binding"] for row in receipt["keys"]],
                                 ["UNBOUND"] * len(CURRENT_KEYS))

        # 3. rawget replaced in ANOTHER loaded file: the read in this file is
        # no longer the builtin's, so it is the reference reported, here.
        line = method + b' ' + read
        column = line.index(b'rawget(_G') + 7 + 1
        for name, write in (("by name", b'\nrawget = function(t, k) return t end\n'),
                            ("through _G", b'\n_G.rawget = function(t, k) return t end\n')):
            with self.subTest(case="rawget replaced in another loaded file " + name):
                files = self.hosted(line)
                files = with_file(files, other, files[other] + write)
                receipt = self.receipt(files)
                self.assertEqual([(problem["path"], problem["construct"], problem["line"],
                                   problem["column"]) for problem
                                  in self.problems(receipt, "binding-mutation")],
                                 [(host, "global-environment", first, column)])
                self.assertEqual([row["binding"] for row in receipt["keys"]],
                                 ["UNBOUND"] * len(CURRENT_KEYS))

    def test_c28_format_arguments_bind_only_when_shown(self):
        # V15 review fix (STD-V15-1, STD-8849-1): a format argument flows to
        # its result only when a static Lua 5.1 format shows it with %s and
        # the call is not known to raise; an ignored, non-text,
        # empty-precision, missing or unknown position never does, nor does
        # any argument of a call with too few proved values or a known
        # incompatible argument, in either call form. gsub and sub can
        # discard the whole text, so they are no transforms at all.
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        shown = lambda call: b'specLabel:SetText(' + call + b')'

        def chain(first, count):
            """A chain of count immutable locals a1..a<count> starting from
            first, in the form of the cf01 review witness, then a %d of the
            last one."""
            links = b''.join(b'local a%d=a%d;' % (index, index - 1)
                             for index in range(2, count + 1))
            return (b'local a1=' + first + b';' + links
                    + shown(b'string.format("%s %d", ' + text + b', a'
                            + str(count).encode() + b')'))
        # Each case acts only on its own site, so one receipt judges them
        # all, site by site (per_site).
        self.per_site((
            ("%s", shown(b'string.format("%s", ' + text + b')'), True),
            ("method %s", shown(b'("[%s]"):format(' + text + b')'), True),
            ("a later %s", shown(b'string.format("%d: %-5s", 1, ' + text + b')'), True),
            ("a static local format",
             b'local fmt = "<" .. "%s>" ' + shown(b'string.format(fmt, ' + text + b')'), True),
            ("a number for %d", shown(b'string.format("%s %d", ' + text + b', 12)'), True),
            ("a numeric string for %d", shown(b'string.format("%s %d", ' + text + b', " 0x1F ")'),
             True),
            # A last call gives exactly the results proved for it, never as
            # many as the format wants and never an assumed one (STD-8849-1,
            # review fix of 7594). Text returns exactly text, source and
            # reason (core/Localization.lua): two strings, then a reason that
            # may be nil; its source is never a number.
            ("an open-ended last argument", shown(b'string.format("%s %s", ' + text + b')'),
             True),
            ("a one-result local function last", b'local function one() return "x" end '
             + shown(b'string.format("%s %s", ' + text + b', one())'), True),
            ("a two-result local function last", b'local function two() return "a", 2 end '
             + shown(b'string.format("%s %s %d", ' + text + b', two())'), True),
            ("method, a one-result local function last", b'local one = function() return "x" end '
             + shown(b'("%s %s"):format(' + text + b', one())'), True),
            # A missing argument raises in every runtime.
            ("four conversions for Text", shown(b'string.format("%s %s %s %s", ' + text + b')'),
             False),
            ("Text's source for %d", shown(b'string.format("%s %d", ' + text + b')'), False),
            ("a no-result local function last", b'local function none() end '
             + shown(b'string.format("%s %s", ' + text + b', none())'), False),
            ("an empty return last", b'local function none() return end '
             + shown(b'string.format("%s %s", ' + text + b', none())'), False),
            ("method, a no-result local function last", b'local none = function() end '
             + shown(b'("%s %s"):format(' + text + b', none())'), False),
            # Whether it returns depends on a field no static rule knows.
            ("a local function that may run off its end", b'local function maybe(x) '
             b'if x then return "x" end end '
             + shown(b'string.format("%s %s", ' + text + b', maybe(specLabel.flag))'), False),
            ("a last method call of unresolved results", b'local o = {} function o:none() end '
             + shown(b'string.format("%s %s", ' + text + b', o:none())'), False),
            ("a one-result last call", b'local function one() return "x" end '
             + shown(b'string.format("%s %s %s", ' + text + b', one())'), False),
            ("a non-number for %d",
             shown(b'string.format("%s %d", ' + text + b', "not-a-number")'), False),
            ("method, a non-number for %d",
             shown(b'("%s %d"):format(' + text + b', "not-a-number")'), False),
            # A nil (or boolean) given to %s: the Lua 5.1 target raises for it
            # (lstrlib.c str_format, luaL_checklstring), so the binder refuses
            # these sites. The commissioned LuaJIT runtime shows such a value
            # instead ("nil", "false"; Text's reason is nil in the checked
            # seams), so for it these four refusals are conservative, not
            # observed errors; the expectations predate the bcf7 review and
            # are unchanged.
            ("three conversions for Text: its reason may be nil",
             shown(b'string.format("%s %s %s", ' + text + b')'), False),
            ("a no-result call before the text", b'local function none() end '
             + shown(b'string.format("%s %s", none(), ' + text + b')'), False),
            ("a nil returned last", b'local function gone() return nil end '
             + shown(b'string.format("%s %s", ' + text + b', gone())'), False),
            ("nil for %s", shown(b'string.format("%s %s", ' + text + b', nil)'), False),
            # Lua cuts a value to one, by position or by parentheses, and the
            # cut value keeps what is known of it (review fix of bcf7). Each
            # refusal below raises before SetText in the commissioned LuaJIT
            # runtime with the real English and Localization: a numeric
            # conversion of nil, a boolean, a table or a non-numeric string.
            # The valid counterparts still bind.
            ("parenthesized zero results for %d", b'local function none() end '
             + shown(b'string.format("%s %d", ' + text + b', (none()))'), False),
            ("method, parenthesized empty return for %d", b'local function none() return end '
             + shown(b'("%s %d"):format(' + text + b', (none()))'), False),
            ("parenthesized nil for %d", shown(b'string.format("%s %d", ' + text + b', (nil))'),
             False),
            ("parenthesized boolean for %d",
             shown(b'string.format("%s %d", ' + text + b', (false))'), False),
            ("parenthesized table for %d", shown(b'string.format("%s %d", ' + text + b', ({}))'),
             False),
            ("a cut zero-result return for %d", b'local function none() end '
             b'local function pair() return none(), "x" end '
             + shown(b'string.format("%s %d %s", ' + text + b', pair())'), False),
            ("a cut nil return for %d", b'local function gone() return nil end '
             b'local function pair() return gone(), "x" end '
             + shown(b'string.format("%s %d %s", ' + text + b', pair())'), False),
            ("a cut non-numeric return for %d", b'local function bad() return "not-a-number" end '
             b'local function pair() return bad(), "x" end '
             + shown(b'string.format("%s %d %s", ' + text + b', pair())'), False),
            ("a last parenthesized zero-result return for %d", b'local function none() end '
             b'local function one() return (none()) end '
             + shown(b'string.format("%s %d", ' + text + b', one())'), False),
            ("a parenthesized call of a reassigned local for %d",
             b'local function one() return 12 end one = function() end '
             + shown(b'string.format("%s %d", ' + text + b', (one()))'), False),
            ("a cut conditional zero result for %d",
             b'local function maybe(x) if not x then return end return 12 end '
             + shown(b'string.format("%d %s", maybe(), ' + text + b')'), False),
            ("parenthesized number for %d", shown(b'string.format("%s %d", ' + text + b', (12))'),
             True),
            ("a parenthesized one-number call for %d", b'local function one() return 12 end '
             + shown(b'string.format("%s %d", ' + text + b', (one()))'), True),
            ("a cut numeric return for %d", b'local function pair() return 12, "x" end '
             + shown(b'string.format("%s %d %s", ' + text + b', pair())'), True),
            # A never-assigned local holds the value of its declaration and is
            # followed to it (SPEC-EFD7-1): each of these eight witnesses
            # raises "number expected" before SetText in the commissioned
            # LuaJIT runtime. Valid number and numeric-string aliases (direct,
            # chained, returned, captured, shadowing) still bind, and a
            # reassigned local is not followed (a value of unknown type).
            ("a boolean alias for %d", b'local bad = false '
             + shown(b'string.format("%s %d", ' + text + b', bad)'), False),
            ("a nil alias for %d", b'local bad = nil '
             + shown(b'string.format("%s %d", ' + text + b', bad)'), False),
            ("a table alias for %d", b'local bad = {} '
             + shown(b'string.format("%s %d", ' + text + b', bad)'), False),
            ("a function alias for %d", b'local bad = function() end '
             + shown(b'string.format("%s %d", ' + text + b', bad)'), False),
            ("a boolean alias chain for %d", b'local first = false local bad = first '
             + shown(b'string.format("%s %d", ' + text + b', bad)'), False),
            ("a returned boolean alias for %d",
             b'local function bad() local v = false return v end '
             + shown(b'string.format("%s %d", ' + text + b', bad())'), False),
            ("a returned nil alias cut for %d",
             b'local function pair() local v = nil return v, "x" end '
             + shown(b'string.format("%s %d %s", ' + text + b', pair())'), False),
            ("a captured boolean alias for %d",
             b'local v = false local function bad() return v end '
             + shown(b'string.format("%s %d", ' + text + b', bad())'), False),
            ("a number alias for %d", b'local n = 12 '
             + shown(b'string.format("%s %d", ' + text + b', n)'), True),
            ("a numeric string alias for %d", b'local n = " 0x1F " '
             + shown(b'string.format("%s %d", ' + text + b', n)'), True),
            ("a number alias chain for %d", b'local first = 12 local n = first '
             + shown(b'string.format("%s %d", ' + text + b', n)'), True),
            ("a returned number alias for %d",
             b'local function num() local v = 12 return v end '
             + shown(b'string.format("%s %d", ' + text + b', num())'), True),
            ("a captured number alias for %d",
             b'local v = 12 local function num() return v end '
             + shown(b'string.format("%s %d", ' + text + b', num())'), True),
            ("a shadowing number alias for %d", b'local bad = false do local bad = 12 '
             + shown(b'string.format("%s %d", ' + text + b', bad)') + b' end', True),
            ("a reassigned local is not followed", b'local n = false n = 12 '
             + shown(b'string.format("%s %d", ' + text + b', n)'), True),
            # Followed to an unresolved call, the alias holds that call's
            # unproved value, refused for a numeric conversion as the call
            # itself is (conservative: its result is not known).
            ("an alias of an unresolved call for %d", b'local n = specLabel:GetCount() '
             + shown(b'string.format("%s %d", ' + text + b', n)'), False),
            # The alias walk is bounded (16 links). Within it the declared
            # value decides; a chain still unfinished at the bound is an
            # unproved value, refused for %d, never an unknown-type value that
            # passes (review fix of cf01). The 17-boolean and the 33 bad-string
            # chains are the review witnesses (LuaJIT raises "number expected"
            # for every bad chain here); the 17-number chain is a valid
            # program the bound refuses conservatively.
            ("a 16-link boolean chain for %d", chain(b'false', 16), False),
            ("a 17-link boolean chain for %d", chain(b'false', 17), False),
            ("a 32-link bad-string chain for %d", chain(b'"not-a-number"', 32), False),
            ("a 33-link bad-string chain for %d", chain(b'"not-a-number"', 33), False),
            ("a 16-link number chain for %d", chain(b'12', 16), True),
            ("a 16-link numeric-string chain for %d", chain(b'" 0x1F "', 16), True),
            ("a 17-link number chain for %d (conservative)", chain(b'12', 17), False),
            ("... as the last argument", b'local function f(...) '
             + shown(b'string.format("%s %s", ' + text + b', ...)') + b' end f("x")', False),
            ("no conversion", shown(b'string.format("fixed", ' + text + b')'), False),
            ("method, no conversion", shown(b'("fixed"):format(' + text + b')'), False),
            ("an unused position", shown(b'string.format("%s", "x", ' + text + b')'), False),
            ("a non-text conversion", shown(b'string.format("%d", ' + text + b')'), False),
            ("an empty precision", shown(b'string.format("%.0s", ' + text + b')'), False),
            ("an escaped percent", shown(b'string.format("%%s", ' + text + b')'), False),
            ("a missing argument raises",
             shown(b'string.format("%s %s %s", ' + text + b', 1)'), False),
            ("an invalid option raises", shown(b'string.format("%y %s", ' + text + b')'), False),
            ("an unknown format", b'local fmt = specLabel.fmt '
             + shown(b'string.format(fmt, ' + text + b')'), False),
            ("sub", shown(b'string.sub(' + text + b', 2, 1)'), False),
            ("gsub", shown(b'string.gsub(' + text + b', ".*", "fixed")'), False),
            ("method sub", shown(text + b':sub(1)'), False)))
        # Without its proved forms the key is unbound, as the gate requires.
        refused = b"\n".join((shown(b'string.format("fixed", ' + text + b')'),
                               shown(b'string.gsub(' + text + b', ".*", "fixed")')))
        self.assert_unbound_exactly(self.receipt(self.hosted(refused)),
                                    ("panel.heading.progress",))

    def test_c29_only_load_time_definitions_define_a_module_function(self):
        # V15 review fix (SPEC-V15-2 unused initializer): a module function or a
        # Nexus export counts only when its file chunk, or an initializer it
        # calls as a statement, runs it at load; an unused or conditional
        # initializer defines nothing, and code run at load before the
        # definition (in the chunk or a called initializer, STD-8849-3)
        # never reaches it. First the real export of ui/Readout.lua, which
        # the charge row's chain (Nexus.Readout.ChargesLine) needs:
        readout = self.files[READOUT]
        export = b"local M = {}\nNexus.Readout = M"
        self.assertEqual(readout.replace(b"\r\n", b"\n").count(export), 1)
        initializer = b"local M = {}\nlocal function Export() Nexus.Readout = M end"
        receipt = self.receipt(with_file(self.files, READOUT, edit(readout, export, initializer)))
        self.assert_unbound_exactly(receipt, (CHARGE,))
        assert_binding_receipt(self, self.receipt(with_file(
            self.files, READOUT, edit(readout, export, initializer + b" Export()"))))
        # The Spec toy: core/UserText.lua replaced by a module whose
        # dispatcher only an initializer defines, with a constant lazy field.
        key = "reason.saved_data_reading"
        undefined = ["T.Message is not defined when its file loads: its definition is not run "
                     "by the file chunk or an initializer it calls"]
        toy = lambda install: TOY_USER_TEXT.replace(b"INSTALL_MARKER", install)
        late = toy(b"").replace(TOY_SHOW, b"").replace(b"setmetatable(T",
                                                       TOY_SHOW + b"Install()\nsetmetatable(T")
        # STD-8849-3: the toy's own display moved into the called
        # initializer, before or after the definition there, or around a
        # nested initializer that defines it.
        installed = toy(b"Install()").replace(TOY_SHOW, b"")
        defining = b"local function Install()\n"
        body_end = b"    end\nend\nInstall()"
        early = installed.replace(defining, defining + TOY_SHOW)
        after = installed.replace(body_end, b"    end\n" + TOY_SHOW + b"end\nInstall()")
        nested = lambda before: installed.replace(defining, b"local function Define()\n").replace(
            body_end, b"    end\nend\nlocal function Install()\n"
            + (TOY_SHOW + b"Define()\n" if before else b"Define()\n" + TOY_SHOW)
            + b"end\nInstall()")
        for source in (early, after, nested(True), nested(False)):
            self.assertEqual(source.count(TOY_SHOW), 1)
        outputs = lambda row: {(output["path"], output["output"])
                               for site in row["sites"] for output in site["outputs"]}
        chunk_output, later_output = (USER_TEXT, "AddMessage"), ("core/Main.lua", "AddMessage")
        for name, source, problems in (
                ("installed", toy(b"Install()"), None),
                # Defined in time for the real later call (core/Main.lua, in
                # a function), not for the toy's chunk code that runs first.
                ("shown by the chunk before it is installed", late, None),
                ("shown by the initializer before it defines it", early, None),
                ("shown by the initializer after it defines it", after, None),
                ("shown before a nested initializer defines it", nested(True), None),
                ("shown after a nested initializer defines it", nested(False), None),
                ("never installed", toy(b"-- Install is never called"), undefined),
                ("installed only conditionally", toy(b"if Nexus.Ready then Install() end"),
                 undefined)):
            with self.subTest(case=name):
                receipt = self.receipt(with_file(self.files, USER_TEXT, source))
                row = self.binding(receipt, key)
                if problems is None:
                    self.assertEqual(row["binding"], "MAPPED_TO_CONSUMER")
                    self.assertTrue(row["sites"])
                    self.assertTrue(all(site["outputs"] for site in row["sites"]))
                    self.assertIn(later_output, outputs(row))
                    self.assertEqual(chunk_output in outputs(row),
                                     source not in (late, early, nested(True)))
                    continue
                self.assertEqual((row["binding"], row["sites"]), ("UNBOUND", []))
                self.assertEqual([problem["detail"] for problem
                                  in self.problems(receipt, "binding-unresolved")], problems)

    def test_c30_a_local_forwarding_wrapper_binds_only_through_one_proved_level(self):
        # The current ui/Readout.lua shape (Permission): a local function
        # hands its own key parameter to the file's direct wrapper TF, which
        # returns the Format result. Here the charge row's only consumer is
        # routed through such a forwarding wrapper over the real T and TF of
        # the real Readout. Each case differs only in the inserted forwarder
        # or in the call. Passing the key on is never enough: the nested
        # result must come back and the site must reach its own output.
        readout = self.files[READOUT]
        lf = readout.replace(b"\r\n", b"\n")
        for real in (b"\nlocal function T(key, english)\n",
                     b"\nlocal function TF(key, args, english)\n",
                     b"\nlocal function Permission(key, setting, value, english, command)\n"
                     b"    return TF(key, {setting = setting, value = value, command = command}, english)\n"):
            self.assertEqual(lf.count(real), 1, real)       # SETUP: the mirrored current shapes
        anchor = b"local QUALITY_NAMES = {"
        line = lf[:lf.index(anchor)].count(b"\n") + 1        # the line of the inserted forwarder
        direct = b'localization.Format("readout.charge_counts",'
        statement = b'local text, source = localization.Format("readout.charge_counts",'
        through = b'ChargeForward("readout.charge_counts",'
        forward = b"local function ChargeForward(key, args) return TF(key, args, nil) end"

        def routed(forwarder, old=direct, new=through):
            data = edit(edit(readout, anchor, forwarder + b"\n" + anchor), old, new)
            return self.receipt(with_file(self.files, READOUT, data))

        def unproven(row):
            return [(site["wrapper"]["name"], site["reason"]) for site in row["unprovenSites"]
                    if site["path"] == READOUT and site["site"] == "wrapper-call"]

        def listed(receipt):
            return sorted((row["construct"], row.get("wrapper")) for row in receipt["dynamicUnknown"]
                          if row["path"] == READOUT
                          and (row["line"] == line or str(row.get("wrapper")).startswith("Charge")))

        def others(receipt):
            return [(problem["code"], problem.get("detail", problem.get("key")), problem.get("method"))
                    for problem in receipt["problems"] if problem["code"] != "binding-unbound"]

        with self.subTest(case="forwarded, returned and shown"):
            receipt = routed(forward)
            assert_binding_receipt(self, receipt)
            row = self.binding(receipt, CHARGE)
            self.assertEqual([(site["site"], site["method"], site["path"], site["wrapper"])
                              for site in row["sites"]],
                             [("wrapper-call", "Format", READOUT,
                               {"name": "ChargeForward", "line": line, "path": READOUT})])
            # The same output as the direct call it replaces (C2).
            self.assertEqual({(output["path"], output["output"])
                              for site in row["sites"] for output in site["outputs"]},
                             {(PANEL, "SetText")})
            # The resolved inner call is no dynamic construct any more.
            self.assertEqual((unproven(row), listed(receipt), others(receipt)), ([], [], []))

        not_returned = [("ChargeForward", "wrapper-result-not-returned")]
        not_shown = [("ChargeForward", "output-not-reached")]
        cases = (
            # (name, forwarder, call replaced, call written,
            #  unproven forwarder sites, listed dynamic rows, other problems)
            ("nested result discarded",
             b'local function ChargeForward(key, args) TF(key, args, nil); return "B:? R:? F:?" end',
             direct, through, not_returned, [], []),
            ("nested result replaced",
             b'local function ChargeForward(key, args) local text = TF(key, args, nil); '
             b'text = "replaced"; return text end',
             direct, through, not_returned, [], []),
            ("direct wrapper discards its consumer-method result",
             b'local function ChargeSeam(key, args) Nexus.Localization.Format(key, args); return "x" end '
             b"local function ChargeForward(key, args) return ChargeSeam(key, args) end",
             direct, through, not_returned, [], []),
            # Readout's own use: lines[#lines + 1] = "- " .. Permission(...).
            ("returned, but only appended to a table", forward, statement,
             b'local lines, text, source = {} lines[#lines + 1] = "- " .. '
             b'ChargeForward("readout.charge_counts",',
             not_shown, [], []),
            ("another call of it is shown, this one is discarded", forward, statement,
             b'local text, source = ChargeForward(charges.key, {}) ChargeForward("readout.charge_counts",',
             not_shown, [("dynamic-wrapper-argument", "ChargeForward")], []),
            # LoadingStatus Clause: T(key) on one path, TF(key, ...) on the other.
            ("Text and Format kinds mixed",
             b"local function ChargeForward(key, args) if args == nil then return T(key, nil) end "
             b"return TF(key, args, nil) end",
             direct, through, [],
             [("dynamic-wrapper-argument", "T"), ("dynamic-wrapper-argument", "TF")], []),
            ("key parameter assigned again",
             b"local function ChargeForward(key, args) key = tostring(key) return TF(key, args, nil) end",
             direct, through, [], [("dynamic-wrapper-argument", "TF")], []),
            ("direct wrapper assigned again",
             b"local function ChargeSeam(key, args) return (Nexus.Localization.Format(key, args)) end "
             b"ChargeSeam = ChargeSeam "
             b"local function ChargeForward(key, args) return ChargeSeam(key, args) end",
             direct, through, [], [],
             [("binding-unresolved", "the wrapper ChargeSeam is assigned again", None)]),
            ("forwarding wrapper assigned again", forward + b" ChargeForward = ChargeForward",
             direct, through, [], [("dynamic-wrapper-argument", "TF")], []),
            ("a cycle without a consumer method",
             b"local function ChargeForward(key, args) return ChargeForward(key, args) end",
             direct, through, [], [], []),
            ("a second forwarding level",
             b"local function ChargeMid(key, args) return TF(key, args, nil) end "
             b"local function ChargeForward(key, args) return ChargeMid(key, args) end",
             direct, through, [], [("dynamic-wrapper-argument", "ChargeMid")], []),
            ("an unrelated caller",
             forward + b" local function ChargeOther(key, args) return nil end",
             direct, b'ChargeOther("readout.charge_counts",', [], [], []),
            ("the literal at another parameter",
             b"local function ChargeForward(label, key, args) return TF(key, args, nil) end",
             direct, b'ChargeForward("readout.charge_counts", charges.key,',
             [], [("dynamic-wrapper-argument", "ChargeForward")], []),
            ("forwarded to a wrapper of the other kind",
             b"local function ChargeForward(key, args) return T(key, nil) end",
             direct, through, [], [], [("binding-kind", CHARGE, "Text")]),
        )
        for name, forwarder, old, new, sites, dynamic, problems in cases:
            with self.subTest(case=name):
                receipt = routed(forwarder, old, new)
                self.assert_unbound_exactly(receipt, (CHARGE,))
                row = self.binding(receipt, CHARGE)
                self.assertEqual(row["sites"], [])
                self.assertEqual((unproven(row), listed(receipt), others(receipt)),
                                 (sites, dynamic, problems))

    def test_c31_the_real_readout_permission_wrapper_is_a_site_without_an_output(self):
        # The real ui/Readout.lua, unedited: each literal key passed to its
        # forwarding wrapper Permission is a Format site through that wrapper,
        # and none is counted: every result is only appended to a returned
        # table or stored in a row field, which is no output. The whole
        # receipt is read here, because these keys are outside the dated 28.
        lf = self.files[READOUT].replace(b"\r\n", b"\n")
        header = b"\nlocal function Permission(key, setting, value, english, command)\n"
        defined = lf[:lf.index(header)].count(b"\n") + 2
        calls = [number for number, text in enumerate(lf.split(b"\n"), 1)
                 if b'Permission("readout.' in text]
        self.assertEqual(len(calls), 13)                    # SETUP: the current literal calls
        receipt = self.catalog.consumer_binding_report(*binding_args(self.files))
        wrapper = {"name": "Permission", "line": defined, "path": READOUT}
        found = sorted((site["line"], site["site"], site["method"], row["binding"], proved,
                        site.get("reason"))
                       for row in receipt["keys"]
                       for proved, sites in ((True, row["sites"]), (False, row["unprovenSites"]))
                       for site in sites
                       if site["path"] == READOUT and site.get("wrapper") == wrapper)
        self.assertEqual(found, [(number, "wrapper-call", "Format", "UNBOUND", False,
                                  "output-not-reached") for number in calls])

    def test_c32_a_later_function_result_is_followed_by_its_own_position_only(self):
        # Lua 5.1 (manual 2.4.3 and 2.5): only a call that is the last
        # expression of a list gives more than its first value, a call in
        # parentheses gives one, and a name without a value gets nil. The
        # current ui/LoadingStatus.lua shape is
        #     return 100, T(key)   and   local percent, progress = M.Progress(status)
        # Each case is one line in its own do block after the proved client
        # label specLabel (per_site). Its site binds only when the localized
        # text stands at the very position that the shown name holds.
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        two = b"local function Two() return 100, " + text + b" end "
        pair = (b"local function Pair(key) local text, source = Nexus.Localization.Text(key) "
                b"return text, source end ")
        pick = b"local function Pick(value) return 1, value end "
        show = b" specLabel:SetText(progress)"
        self.per_site((
            ("the second result of a local function",
             two + b"local percent, progress = Two()" + show, True),
            ("the current shape: a wrapper call returned second, shown in a concatenation",
             b"local function T(key) return (Nexus.Localization.Text(key)) end "
             b'local function Progress() return 100, T("panel.heading.progress") end '
             b'local percent, progress = Progress() specLabel:SetText("Local: " .. progress)', True),
            ("assigned later from the call",
             two + b"local percent, progress percent, progress = Two()" + show, True),
            ("a tail call keeps the position",
             two + b"local function Tail() return Two() end local percent, progress = Tail()" + show,
             True),
            ("a tail call behind one value moves the position by one",
             two + b"local function Shift() return 0, Two() end local a, b, progress = Shift()" + show,
             True),
            ("the result beside it stays a number",
             two + b"local function Shift() return 0, Two() end local a, progress, c = Shift()" + show,
             False),
            ("a value passed in returns second to its own call",
             pick + b"local a, progress = Pick(" + text + b') local c, d = Pick("plain")' + show, True),
            ("and not to another call of that function",
             pick + b"local a, b = Pick(" + text + b') local c, progress = Pick("plain")' + show, False),
            # The first value behaves as before, and only it carries the text.
            ("the first result is followed as before",
             pair + b'local progress, status = Pair("panel.heading.progress")' + show, True),
            ("a wrapper's returned status is not its text",
             pair + b'local shown, progress = Pair("panel.heading.progress")' + show, False),
            ("the consumer method's own status is not its text",
             b"local shown, progress = " + text + show, False),
            ("a tail call of the consumer method passes no status on as text",
             b"local function Tail() return " + text + b" end local shown, progress = Tail()" + show,
             False),
            ("a first result is not the second",
             b"local function Lead() return " + text + b", 100 end local shown, progress = Lead()"
             + show, False),
            ("a function returning one value gives no second",
             b"local function One() return (" + text + b") end local shown, progress = One()" + show,
             False),
            ("a shorter return path adds nothing to a later position",
             b"local function Few(flag) if flag then return 100 end return 100, 200, " + text
             + b" end local a, progress = Few(true)" + show, False),
            ("the names swapped", two + b"local progress, percent = Two()" + show, False),
            ("a call that is not last gives its first value only",
             two + b"local percent, progress = Two(), nil" + show, False),
            ("a call in parentheses gives its first value only",
             two + b"local percent, progress = (Two())" + show, False),
            ("a tail call in parentheses gives its first value only",
             two + b"local function Tail() return (Two()) end local percent, progress = Tail()" + show,
             False),
            ("a call that is not last in a return gives its first value only",
             two + b"local function Mid() return Two(), 0 end local a, b, progress = Mid()" + show,
             False),
            ("overwritten before it is shown",
             two + b'local percent, progress = Two() progress = "none"' + show, False),
            ("read by a nested function",
             two + b"local percent, progress = Two() local function Show()" + show + b" end Show()",
             False),
            ("the function assigned again",
             two + b"Two = Two local percent, progress = Two()" + show, False),
            ("an unresolved callee",
             b"local percent, progress = select(1, 100, " + text + b")" + show, False),
            ("results through pcall",
             b"local function One() return " + text + b" end local ok, progress = pcall(One)" + show,
             False),
            ("results through ...",
             b"local function Var(...) return ... end local percent, progress = Var(100, " + text
             + b")" + show, False),
        ))

    def test_c33_the_real_loading_status_text_reaches_update_and_stops_at_its_receiver(self):
        # The real ui/LoadingStatus.lua on a real-bytes substrate of the
        # registry inputs and that file alone (built as s8_cohort_files
        # builds the cohort, so nothing else can show these keys). M.Progress
        # returns its sentence as its second value, and M.Update shows it
        # with f.detail:SetText. The whole receipt is read: these keys are
        # outside the dated 28. What is measured is the proved output of
        # each key, never only a site.
        loading = "ui/LoadingStatus.lua"
        full = self.full_files
        wanted = set(INPUTS) | {loading}
        toc = b"".join(line for line in full["Nexus.toc"].splitlines(True)
                       if not line.strip() or line.strip().startswith(b"#")
                       or line.strip().replace(b"\\", b"/").decode("utf-8") in wanted)
        companion = set(toc_listing(CONSUMER_TOCS[1], full[CONSUMER_TOCS[1]]))
        base = {path: data for path, data in full.items()
                if path in wanted or path in CONSUMER_TOCS or path in companion}
        base["Nexus.toc"] = toc
        real = full[loading]
        lf = real.replace(b"\r\n", b"\n")
        call = b"local percent,progress=M.Progress(status)"
        shown = b'f.detail:SetText(localText.."\\n"..progress)'
        for line in (b'    if status.state=="ready" then return 100,T("loading.status.ready") end\n',
                     b"    local f=EnsureFrame()\n", b"    " + call + b"\n", b"    " + shown + b"\n"):
            self.assertEqual(lf.count(line), 1, line)       # SETUP: the current path
        second = ("loading.status.ready", "loading.status.see_status_for_reason",
                  "loading.status.current_step_counted", "loading.status.current_step_records_read",
                  "loading.status.current_step_in_progress")
        for key in second + ("loading.status.elapsed", "loading.button.wishlists"):
            self.assertEqual(lf.count(b'"' + key.encode() + b'"'), 1, key)      # SETUP: one site each

        def measured(data, keys=second):
            receipt = self.catalog.consumer_binding_report(
                *binding_args(with_file(base, loading, data)))
            rows = {row["key"]: row for row in receipt["keys"]}
            return {key: (rows[key]["binding"],
                          sorted({(site["path"], output["output"])
                                  for site in rows[key]["sites"] for output in site["outputs"]}),
                          sorted((site["path"], site["reason"])
                                 for site in rows[key]["unprovenSites"]))
                    for key in keys}

        unshown = ("UNBOUND", [], [(loading, "output-not-reached")])
        tooltip = ("DIRECT_LITERAL_CONSUMER", [(loading, "AddLine")], [])
        swapped = edit(real, shown, b'GameTooltip:AddLine(localText.."\\n"..progress)')
        # Receiver-blocked control (C35 proves the unedited receiver): one
        # more assignment of the frame cache, so EnsureFrame is no singleton
        # cache helper and f in M.Update is again only a call result. The two
        # cases that rest on a blocked receiver keep their expectations.
        self.assertEqual(lf.count(b"\nlocal frame, lastSnapshot, startedAt, completedAt\n"), 1)
        blocked = real + b"\nlocal function Forget() frame=nil end\n"
        with self.subTest(case="the frame cache assigned elsewhere: the receiver is not proved"):
            # The second value reaches the SetText call, but no output is
            # counted there: f is the result of the local function
            # EnsureFrame(), and a receiver field is proved only on a tracked
            # object, which such a call result is not. The elapsed line, shown
            # directly on f.progress, stops at the same receiver; the button
            # text, set where f is the CreateFrame local itself, is proved.
            self.assertEqual(
                measured(blocked, second + ("loading.status.elapsed", "loading.button.wishlists")),
                dict({key: unshown for key in second + ("loading.status.elapsed",)},
                     **{"loading.button.wishlists":
                        ("DIRECT_LITERAL_CONSUMER", [(loading, "SetText")], [])}))
        with self.subTest(case="only the receiver changed to a proved client object"):
            self.assertEqual(measured(swapped), {key: tooltip for key in second})
        with self.subTest(case="through the Nexus export, shown by a proved client object"):
            self.assertEqual(
                measured(blocked + b"\ndo local percent, progress = Nexus.LoadingStatus.Progress("
                         b"Snapshot()) GameTooltip:AddLine(progress) end\n"),
                {key: tooltip for key in second})
        with self.subTest(case="the module function defined twice"):
            self.assertEqual(
                measured(swapped + b'\nfunction M.Progress(status) return nil, "replaced" end\n'),
                {key: unshown for key in second})
        with self.subTest(case="called through a local alias of the module function"):
            self.assertEqual(
                measured(edit(swapped, call, b"local Progress=M.Progress "
                              b"local percent,progress=Progress(status)")),
                {key: unshown for key in second})

    def test_c34_a_receiver_field_follows_a_helper_result_only_for_a_singleton_cache(self):
        # The current ui/LoadingStatus.lua shape: a file-level cache, a
        # helper that returns it when set, else makes the frame, stores it at
        # once and returns it; callers then use fields of the result as
        # receivers. Only that exact shape makes every result one object.
        # Each case is one line in its own do block (per_site), with its own
        # field name, so no case can lend a widget to another.
        text = b'Nexus.Localization.Text("panel.heading.progress")'
        widget = b' = %s:CreateFontString(nil, "OVERLAY") '

        def make(field, head=b"local cache ", guard=b"if cache then return cache end ",
                 create=b'local w = CreateFrame("Frame") ', store=b"cache = w ", fill=True,
                 tail=b"return w end "):
            filled = b"w." + field + widget % b"w" if fill else b""
            return head + b"local function Make() " + guard + create + store + filled + tail

        def show(field, holder=b"a"):
            return holder + b"." + field + b":SetText(" + text + b")"

        one = b"local a = Make() "
        two = b"local a = Make() local b = Make() "
        self.per_site((
            ("a cached factory: the widget set in the helper is the holder's",
             make(b"specA") + one + show(b"specA"), True),
            ("two holders of a cached factory are one object",
             make(b"specB", fill=False) + two + b"a.specB" + widget % b"a" + show(b"specB", b"b"),
             True),
            ("its object read by a nested function only (a script handler)",
             make(b"specC", tail=b'w:SetScript("OnHide", function() w:Show() end) return w end ')
             + one + show(b"specC"), True),
            # The critical control: two results of ONE uncached helper are two
            # objects; the widget set on a is not b's.
            ("two callers of one uncached factory: b does not borrow the widget set on a",
             b'local function Make() local w = CreateFrame("Frame") return w end ' + two
             + b"a.specD" + widget % b"a" + show(b"specD", b"b"), False),
            ("stored but never returned from the cache: every call makes a new object",
             make(b"specE", guard=b"", fill=False) + two + b"a.specE" + widget % b"a"
             + show(b"specE", b"b"), False),
            ("another field of the cached object", make(b"specF") + one + show(b"specFother"), False),
            ("the cache unset elsewhere",
             make(b"specG") + b"local function Reset() cache = nil end " + one + show(b"specG"), False),
            ("the cache given another table elsewhere",
             make(b"specH") + b"local function Swap() cache = {} end " + one + show(b"specH"), False),
            ("the cache not nil at first",
             make(b"specI", head=b'local cache = CreateFrame("Frame") ') + one + show(b"specI"), False),
            ("a return of another object",
             make(b"specJ", head=b'local cache local spare = CreateFrame("Frame") ',
                  tail=b"if Nexus.Flag then return spare end return w end ") + one + show(b"specJ"),
             False),
            ("a scalar return",
             make(b"specK", tail=b"if Nexus.Flag then return 1 end return w end ") + one
             + show(b"specK"), False),
            ("a return without a value",
             make(b"specL", tail=b"if Nexus.Flag then return end return w end ") + one
             + show(b"specL"), False),
            ("a path that returns nothing at its end",
             make(b"specM", tail=b"if Nexus.Flag then return w end end ") + one + show(b"specM"),
             False),
            ("the helper assigned again",
             make(b"specN") + b"Make = Make " + one + show(b"specN"), False),
            ("the helper called through an alias",
             make(b"specO") + b"local Other = Make local a = Other() " + show(b"specO"), False),
            ("two helpers storing into one cache",
             make(b"specP") + b"local function Again() if cache then return cache end "
             b'local w = CreateFrame("Frame") cache = w return w end ' + one + show(b"specP"), False),
            ("the helper's object assigned again",
             make(b"specQ", store=b'cache = w w = CreateFrame("Frame") ') + one + show(b"specQ"),
             False),
            ("the helper's object assigned by a nested function",
             make(b"specR", tail=b"local function Drop() w = nil end return w end ") + one
             + show(b"specR"), False),
            ("the cache stored only after other code ran",
             make(b"specS", create=b'local w = CreateFrame("Frame") w:Hide() ') + one
             + show(b"specS"), False),
            ("a call among the creator's arguments",
             make(b"specT", head=b"local cache local function Parent() return UIParent end ",
                  create=b'local w = CreateFrame("Frame", nil, Parent()) ') + one + show(b"specT"),
             False),
            ("a helper with a parameter",
             b"local cache local function Make(kind) if cache then return cache end "
             b"local w = CreateFrame(kind) cache = w w.specU" + widget % b"w"
             + b'return w end local a = Make("Frame") ' + show(b"specU"), False),
            ("the cache a local of an enclosing function",
             b"local function Outer() " + make(b"specV") + one + show(b"specV") + b" end Outer()",
             False),
            ("a conflicting value set through another holder",
             make(b"specW") + two + b'b.specW = "plain" ' + show(b"specW"), False),
            ("the widget set on another object only",
             make(b"specX", fill=False) + b'local other = CreateFrame("Frame") other.specX'
             + widget % b"other" + one + show(b"specX"), False),
            ("a holder assigned again",
             make(b"specY") + one + b"a = Make() " + show(b"specY"), False),
            # Review S1: only literals and plain names may be creator
            # arguments, as in the real CreateFrame("Frame", "Name", UIParent).
            ("literal and plain-name creator arguments",
             make(b"specArgs", create=b'local w = CreateFrame("Frame", "SpecNamedFrame", UIParent) ')
             + one + show(b"specArgs"), True),
            # Root's reproduced case, byte for byte: the index argument runs
            # an __index of the loaded source before the store; that call of
            # the helper makes and stores another frame, so a and b are two
            # objects and b has no such field.
            ("an index among the creator's arguments can re-enter the helper",
             b"local cache local args = {} local active = false local observed "
             b"local function Make() if cache then return cache end "
             b'local w = CreateFrame("Frame", args.name) cache = w return w end '
             b"setmetatable(args, {__index = function() if not active then active = true "
             b'local a = Make() a.specReentry = a:CreateFontString(nil, "OVERLAY") observed = a end '
             b"return nil end}) local b = Make() "
             b'b.specReentry:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("an operator among the creator's arguments",
             make(b"specConcat", head=b'local cache local prefix = "Spec" ',
                  create=b'local w = CreateFrame("Frame", prefix .. "Frame") ') + one
             + show(b"specConcat"), False),
            # Review S2, Root's three reproduced cases, byte for byte: another
            # result of the same helper is the same frame. A use of the helper
            # that is no directly declared holder refuses the helper as a
            # whole, so the string written through g cannot go unseen.
            ("a conflicting value through a parenthesized call of the helper",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w w.specParen=w:CreateFontString(nil,"OVERLAY") '
             b'return w end local a=Make() local g = (Make()) g.specParen="plain" '
             b'a.specParen:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a conflicting value through an alias of the helper",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w w.specAlias=w:CreateFontString(nil,"OVERLAY") '
             b'return w end local a=Make() local Other=Make local g=Other() g.specAlias="plain" '
             b'a.specAlias:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a conflicting value through a function that returns the helper's call",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w w.specWrap=w:CreateFontString(nil,"OVERLAY") '
             b"return w end local a=Make() local function Get() return Make() end local g=Get() "
             b'g.specWrap="plain" '
             b'a.specWrap:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            # Review S3: an output method replaced through one holder of a
            # cached frame is replaced for every holder; two results of an
            # uncached factory stay two frames, so b keeps its own method.
            ("an output method replaced through another holder of the cached frame",
             make(b"specMethod", fill=False) + two + b"a.AddMessage = function() end b:AddMessage("
             + text + b")", False),
            ("the same replacement on one of two uncached frames leaves the other its method",
             b'local function Make() local w = CreateFrame("Frame") return w end ' + two
             + b"a.AddMessage = function() end b:AddMessage(" + text + b")", True),
            # Review S4, Root's two reproduced cases, byte for byte. A cache
            # declared with nil has two definitions, so an alias of it was a
            # separate object and the string written through it went unseen:
            # that declaration form is refused. A cache declared without a
            # value has the store as its only definition, so its alias is the
            # same frame and the conflicting write refuses the receiver. (With
            # review F1 an alias of the cache refuses the helper as a whole;
            # the row stays unbound either way.)
            ("a cache declared with an explicit nil: a conflicting value through its alias",
             b"local cache = nil local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specExplicitNil=w:CreateFontString(nil,"OVERLAY") return w end '
             b'local a=Make() local g=cache g.specExplicitNil="plain" '
             b'a.specExplicitNil:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a cache declared without a value: a conflicting value through its alias",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specNoInit=w:CreateFontString(nil,"OVERLAY") return w end '
             b'local a=Make() local g=cache g.specNoInit="plain" '
             b'a.specNoInit:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            # Review F1, Root's four reproduced cases, byte for byte. In each
            # the cached frame reaches a local g that the object model takes
            # for another object, and a string is written through g. A name
            # that holds the frame and is handed on (returned by another
            # function, stored in a field, passed to a function; the cache
            # returned elsewhere) refuses the helper as a whole.
            ("a holder returned by another function, then written through",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w w.specFwdRet=w:CreateFontString(nil,"OVERLAY") '
             b"return w end local function Get() local x=Make() return x end local a=Make() "
             b'local g=Get() g.specFwdRet="plain" '
             b'a.specFwdRet:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a holder stored in a field and read back, then written through",
             b"local cache local box={} local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w w.specFwdFld=w:CreateFontString(nil,"OVERLAY") '
             b"return w end local a=Make() box.held=a local g=box.held "
             b'g.specFwdFld="plain" '
             b'a.specFwdFld:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("the cache returned by another function, then written through",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specFwdCache=w:CreateFontString(nil,"OVERLAY") return w end '
             b"local function Peek() return cache end local a=Make() local g=Peek() "
             b'g.specFwdCache="plain" '
             b'a.specFwdCache:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a holder passed to a function reached through a field, which writes through it",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w w.specFwdArg=w:CreateFontString(nil,"OVERLAY") '
             b'return w end local a=Make() Nexus.SpecTake=function(o) o.specFwdArg="plain" end '
             b"Nexus.SpecTake(a) "
             b'a.specFwdArg:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            # The same class, found while closing F1: a method call hands the
            # frame to the function the file itself stored on it.
            ("a function stored on a holder and called as its method writes through its argument",
             make(b"specFwdMeth") + one
             + b'a.Refresh = function(self) self.specFwdMeth = "plain" end a:Refresh() '
             + show(b"specFwdMeth"), False),
            # What stays admitted: the uses of the real helper and of its
            # caller. The frame as an index base, a method receiver and in a
            # test; the helper's own local as the parent given to the creator
            # and read by a nested function.
            ("a holder used as an index base, a method receiver and in a test",
             make(b"specUse") + one
             + b"if a then a:SetAlpha(1) end a.specNote = 1 local n = a.specNote "
             + show(b"specUse"), True),
            ("the helper's object given to the creator as a parent and read by a handler",
             make(b"specParent", tail=b'local child = CreateFrame("Frame", nil, w) '
                  b'child:SetScript("OnHide", function() w:Show() end) return w end ')
             + one + show(b"specParent"), True),
            ("a same-named field of an unrelated fresh table",
             make(b"specRec") + one + b'local rec = {} rec.specRec = "plain" '
             + show(b"specRec"), True),
            # Reviews G1/S5 and S6, Root's seven programs, byte for byte. A
            # write with a computed key through a name that holds the frame
            # is not recorded as a field write: it can overwrite the receiver
            # field or store a method unseen. An arithmetic or concatenation
            # operand hands the frame to the other operand's metamethod. Each
            # refuses the helper. The last two were already refused: an
            # and/or expression used as a value can be the frame itself.
            ("a computed-key write through a holder overwrites the field",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specKeyWrite=w:CreateFontString(nil,"OVERLAY") return w end '
             b'local a=Make() local k="specKeyWrite" a[k]="plain" '
             b'a.specKeyWrite:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a computed-key write through a holder stores a method that takes the frame",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specKeyMeth=w:CreateFontString(nil,"OVERLAY") return w end '
             b'local a=Make() local k="Refresh" '
             b'a[k]=function(self) self.specKeyMeth="plain" end a:Refresh() '
             b'a.specKeyMeth:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a computed-key write through the helper's own local",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specKeyObj=w:CreateFontString(nil,"OVERLAY") local k="specKeyObj" '
             b'w[k]="plain" return w end local a=Make() '
             b'a.specKeyObj:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a holder as an arithmetic operand reaches the other operand's __add",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specArith=w:CreateFontString(nil,"OVERLAY") return w end local a=Make() '
             b'local trap=setmetatable({}, {__add=function(x,y) x.specArith="plain" return 0 end}) '
             b"local n=a+trap "
             b'a.specArith:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("a holder as a tested concatenation operand reaches the other operand's __concat",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specConcat=w:CreateFontString(nil,"OVERLAY") return w end local a=Make() '
             b'local trap=setmetatable({}, {__concat=function(x,y) x.specConcat="plain" '
             b'return "" end}) if a..trap then end '
             b'a.specConcat:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("an or expression used as a value can be the holder itself",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specOr=w:CreateFontString(nil,"OVERLAY") return w end local a=Make() '
             b'local g=a or {} g.specOr="plain" '
             b'a.specOr:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("an and expression used as a value can be the holder itself",
             b"local cache local function Make() if cache then return cache end "
             b'local w=CreateFrame("Frame") cache=w '
             b'w.specAnd=w:CreateFontString(nil,"OVERLAY") return w end local a=Make() '
             b'local g=true and a g.specAnd="plain" '
             b'a.specAnd:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            # The same class by precedence: not a ^ b is not (a ^ b), so the
            # holder is an operand of ^ although it stands right after not.
            ("a holder after not is still the operand of a following ^",
             make(b"specPow") + one
             + b'local trap = setmetatable({}, {__pow = function(x, y) x.specPow = "plain" '
             b"return 0 end}) local n = not a ^ trap " + show(b"specPow"), False),
            # What stays admitted: values that are only tested or compared,
            # and a read with a computed key.
            ("a holder under not, in comparisons and in a tested and/or chain",
             make(b"specBool") + one
             + b"local same = a == nil if not a or a ~= nil and (a and a.specFlag) then end "
             + show(b"specBool"), True),
            ("a read through a holder with a computed key",
             make(b"specRead") + one + b'local k = "specRead" local v = a[k] '
             + show(b"specRead"), True),
            # The older direct-frame defect (Spec O1): no helper at all. A
            # write with a computed key through a plain name that may hold the
            # frame is no recorded field write, so the receiver field was
            # proved although the write can overwrite it. Root's program,
            # byte for byte, then the same object reached in other ways. Each
            # case has its own frame, names and field.
            ("a computed-key write on a directly created frame overwrites the field",
             b'local f=CreateFrame("Frame") f.existingDirect=f:CreateFontString(nil,"OVERLAY") '
             b'local k="existingDirect" f[k]="plain" '
             b'f.existingDirect:SetText(Nexus.Localization.Text("panel.heading.progress"))', False),
            ("the key is a concatenation",
             b'local dCat = CreateFrame("Frame") dCat.specT1Cat' + widget % b"dCat"
             + b'dCat["specT1" .. "Cat"] = "plain" ' + show(b"specT1Cat", b"dCat"), False),
            ("the key is a call result",
             b'local function specT1KeyName() return "specT1Call" end '
             b'local dCall = CreateFrame("Frame") dCall.specT1Call' + widget % b"dCall"
             + b'dCall[specT1KeyName()] = "plain" ' + show(b"specT1Call", b"dCall"), False),
            ("the write goes through an unassigned local alias of the frame",
             b'local dAlias = CreateFrame("Frame") dAlias.specT1Alias' + widget % b"dAlias"
             + b'local gAlias = dAlias local kAlias = "specT1Alias" gAlias[kAlias] = "plain" '
             + show(b"specT1Alias", b"dAlias"), False),
            ("the receiver is read through the alias and the write goes through the frame",
             b'local dVia = CreateFrame("Frame") dVia.specT1Via' + widget % b"dVia"
             + b'local gVia = dVia local kVia = "specT1Via" dVia[kVia] = "plain" '
             + show(b"specT1Via", b"gVia"), False),
            ("the write is made by a resolved local helper through its parameter",
             b"local function specT1Put(t, key, value) t[key] = value end "
             b'local dParam = CreateFrame("Frame") dParam.specT1Param' + widget % b"dParam"
             + b'specT1Put(dParam, "specT1Param", "plain") '
             + show(b"specT1Param", b"dParam"), False),
            ("a pairs loop copies a table into the frame",
             b'local dCopy = CreateFrame("Frame") dCopy.specT1Copy' + widget % b"dCopy"
             + b'for name, value in pairs({specT1Copy = "plain"}) do dCopy[name] = value end '
             + show(b"specT1Copy", b"dCopy"), False),
            # Not flow-sensitive: the write stands after the call, and the
            # field is refused all the same, as after a literal write there.
            ("the computed-key write stands after the SetText call",
             b'local dLate = CreateFrame("Frame") dLate.specT1Late' + widget % b"dLate"
             + show(b"specT1Late", b"dLate")
             + b' local kLate = "specT1Late" dLate[kLate] = "plain"', False),
            # The value is not kept, so even a widget written under an
            # unknown key refuses the field (no false proof either way).
            ("a widget written with a computed key",
             b'local dWidget = CreateFrame("Frame") dWidget.specT1Widget' + widget % b"dWidget"
             + b'local kWidget = "specT1Widget" dWidget[kWidget]' + widget % b"dWidget"
             + show(b"specT1Widget", b"dWidget"), False),
            # What stays proved: no computed-key write can reach the frame.
            ("a directly created frame without any computed-key write",
             b'local dPlain = CreateFrame("Frame") dPlain.specT1Plain' + widget % b"dPlain"
             + show(b"specT1Plain", b"dPlain"), True),
            ("a read through the frame with a computed key",
             b'local dGet = CreateFrame("Frame") dGet.specT1Get' + widget % b"dGet"
             + b'local kGet = "specT1Get" local vGet = dGet[kGet] '
             + show(b"specT1Get", b"dGet"), True),
            ("a computed-key write on an unrelated fresh table",
             b'local dOther = CreateFrame("Frame") dOther.specT1Other' + widget % b"dOther"
             + b'local tOther = {} local kOther = "specT1Other" tOther[kOther] = "plain" '
             + show(b"specT1Other", b"dOther"), True),
            ("a computed-key write on a second frame of its own CreateFrame call",
             b'local dFirst = CreateFrame("Frame") local dSecond = CreateFrame("Frame") '
             b"dFirst.specT1Second" + widget % b"dFirst"
             + b'local kSecond = "specT1Second" dSecond[kSecond] = "plain" '
             + show(b"specT1Second", b"dFirst"), True),
            ("literal writes of other fields of the same frame, in both spellings",
             b'local dKeep = CreateFrame("Frame") dKeep.specT1Keep' + widget % b"dKeep"
             + b'dKeep.specT1Else = "plain" dKeep["specT1Else2"] = "plain" '
             + show(b"specT1Keep", b"dKeep"), True),
            ("a computed-key write on a table kept in a field of the frame",
             b'local dNest = CreateFrame("Frame") dNest.specT1Nest' + widget % b"dNest"
             + b'dNest.data = {} local kNest = "specT1Nest" dNest.data[kNest] = "plain" '
             + show(b"specT1Nest", b"dNest"), True),
        ))

    def test_c35_the_real_loading_status_frame_is_one_cached_object_for_its_receivers(self):
        # The real ui/LoadingStatus.lua, unedited, on the C33 substrate (the
        # registry inputs and that file alone). EnsureFrame is a singleton
        # cache helper, so f in M.Update is the frame whose detail and
        # progress fields EnsureFrame set to font strings: f.detail:SetText
        # and f.progress:SetText are client outputs. The proved output of
        # each key is measured, on the whole receipt. This substrate is that
        # one file only. It says nothing about the full repository, which is
        # measured apart: there Root's receipt proves the elapsed line on
        # f.progress and not the f.detail outputs, for a cause not yet
        # established.
        loading = "ui/LoadingStatus.lua"
        full = self.full_files
        wanted = set(INPUTS) | {loading}
        toc = b"".join(line for line in full["Nexus.toc"].splitlines(True)
                       if not line.strip() or line.strip().startswith(b"#")
                       or line.strip().replace(b"\\", b"/").decode("utf-8") in wanted)
        companion = set(toc_listing(CONSUMER_TOCS[1], full[CONSUMER_TOCS[1]]))
        base = {path: data for path, data in full.items()
                if path in wanted or path in CONSUMER_TOCS or path in companion}
        base["Nexus.toc"] = toc
        real = full[loading]
        lf = real.replace(b"\r\n", b"\n")
        for lines in (b"\nlocal frame, lastSnapshot, startedAt, completedAt\n",
                      b"\nlocal function EnsureFrame()\n    if frame then return frame end\n"
                      b'    local f=CreateFrame("Frame","NexusLoadingStatusFrame",UIParent)\n'
                      b"    frame=f\n",
                      b"\n    return f\nend\nfunction M.Update(status,force)\n",
                      b"\n    local f=EnsureFrame()\n",
                      b"\n    local percent,progress=M.Progress(status)\n",
                      b'\n    f.detail:SetText(localText.."\\n"..progress)\n',
                      b'\n    f.progress:SetText(status.state=="ready" and "" or '
                      b'TF("loading.status.elapsed",\n'):
            self.assertEqual(lf.count(lines), 1, lines)     # SETUP: the current shape
        second = ("loading.status.ready", "loading.status.see_status_for_reason",
                  "loading.status.current_step_counted", "loading.status.current_step_records_read",
                  "loading.status.current_step_in_progress")
        elapsed, button = "loading.status.elapsed", "loading.button.wishlists"
        for key in second + (elapsed, button):
            self.assertEqual(lf.count(b'"' + key.encode() + b'"'), 1, key)      # SETUP: one site each

        def measured(data):
            receipt = self.catalog.consumer_binding_report(
                *binding_args(with_file(base, loading, data)))
            rows = {row["key"]: row for row in receipt["keys"]}
            return {key: (rows[key]["binding"],
                          sorted({(site["path"], output["output"])
                                  for site in rows[key]["sites"] for output in site["outputs"]}),
                          sorted((site["path"], site["reason"])
                                 for site in rows[key]["unprovenSites"]))
                    for key in second + (elapsed, button)}

        label = ("DIRECT_LITERAL_CONSUMER", [(loading, "SetText")], [])
        unshown = ("UNBOUND", [], [(loading, "output-not-reached")])
        with self.subTest(case="the unedited file"):
            # The five second-value sentences on f.detail, the elapsed line on
            # f.progress, and, as before, the button text on f.localButton.
            self.assertEqual(measured(real), {key: label for key in second + (elapsed, button)})
        with self.subTest(case="a conflicting value set on the same frame through another holder"):
            # g is the same cached frame, so its detail field is no longer
            # only a font string; the progress field is untouched.
            self.assertEqual(
                measured(real + b'\ndo local g = EnsureFrame() g.detail = "plain" end\n'),
                dict({key: unshown for key in second}, **{elapsed: label, button: label}))
        with self.subTest(case="the helper assigned again"):
            self.assertEqual(
                measured(real + b"\nEnsureFrame = EnsureFrame\n"),
                dict({key: unshown for key in second + (elapsed,)}, **{button: label}))

    def test_c36_the_real_user_text_accessor_wrappers_and_reason_keys_bind_through_message(self):
        # core/UserText.lua fetches the seam through its local accessor Seam
        # (the seam table, or nil). Its wrappers Say, SayF and SeamReason are
        # wrappers only through that accessor, and T.Message's first dispatch
        # is guarded by the reasons table, parallel to its map reasonKeys.
        # Real bytes and unviewed receipts: these keys are outside the dated
        # cohort. Every expectation is of T.Message's own first result, the
        # route the dated mapped reasons already take.
        user = self.files[USER_TEXT]
        lf = user.replace(b"\r\n", b"\n")
        report = self.catalog.consumer_binding_report
        every = MESSAGE_KEYS + REASON_KEYS
        self.assertEqual((len(MESSAGE_KEYS), len(REASON_KEYS), len(set(every))), (12, 36, 48))

        def line_of(source, needle):
            source = source.replace(b"\r\n", b"\n")
            self.assertEqual(source.count(needle), 1, needle)
            return source[:source.index(needle)].count(b"\n") + 1

        def judged(files):
            receipt = report(*binding_args(files))
            rows = {row["key"]: row for row in receipt["keys"]}
            other = [(problem["path"], problem.get("line"), problem.get("construct"),
                      problem.get("detail"))
                     for problem in receipt["problems"] if problem["code"] != "binding-unbound"]
            return receipt, rows, {key: rows[key]["binding"] for key in every}, other

        def here(rows, key, field):
            return [site for site in rows[key][field] if site["path"] == USER_TEXT]

        bound = dict(dict.fromkeys(MESSAGE_KEYS, "DIRECT_LITERAL_CONSUMER"),
                     **dict.fromkeys(REASON_KEYS, "MAPPED_TO_CONSUMER"))
        receipt, rows, bindings, other = judged(self.files)
        self.assertEqual(other, [])
        self.assertEqual(bindings, bound)
        chain = map_chain(self, receipt, "SeamReason")
        self.assertTrue(chain_outputs(chain))
        for key in MESSAGE_KEYS:
            with self.subTest(key=key):
                sites = here(rows, key, "sites")
                self.assertEqual([(site["site"], site["line"]) for site in sites],
                                 [("wrapper-call", line_of(lf, b'("' + key.encode() + b'"'))])
                self.assertIn(sites[0]["wrapper"]["name"], ("Say", "SayF"))
                self.assertEqual({(output["path"], output["output"])
                                  for output in sites[0]["outputs"]}, chain_outputs(chain))
        mapped = [site for key in REASON_KEYS for site in rows[key]["sites"]]
        self.assertEqual(len(mapped), 39)
        self.assertEqual({(site["site"], site["path"], site["map"], site["dispatcher"])
                          for site in mapped},
                         {("map-value", USER_TEXT, "reasonKeys", DISPATCHER)})
        # Normal against forced replay: the permanent guard of prove's use of
        # one single-root search for every key with that same root (here the
        # 34 single-entry keys of reasonKeys and the dated mapped reasons).
        # The same cohort inputs once more, with single_root_replay forced on
        # the one linker that call builds: every root is then searched on its
        # own under its key's allowed set and no kept result is used. The
        # two complete unviewed receipts must be equal, no field masked. The
        # constructor is restored whatever happens, so no later receipt of
        # this or another test is made in that mode.
        linker_class = self.catalog._Linker
        constructor = linker_class.__dict__["__init__"]
        forced = []

        def replaying(linker, *args, **kwargs):
            constructor(linker, *args, **kwargs)
            forced.append(getattr(linker, "single_root_replay", None))
            linker.single_root_replay = True

        linker_class.__init__ = replaying
        try:
            replayed = report(*binding_args(self.files))
        finally:
            linker_class.__init__ = constructor
        self.assertIs(linker_class.__dict__["__init__"], constructor)
        # Exactly one linker was built for that call, with the switch off by
        # default, so the replay was really forced and nothing else was.
        self.assertEqual(forced, [False])
        self.assertIs(type(replayed), dict)
        self.assertEqual(sorted(field for field in set(receipt) | set(replayed)
                                if field not in receipt or field not in replayed
                                or receipt[field] != replayed[field]), [])
        self.assertTrue(replayed == receipt)
        # Every real dispatcher caller disconnected (as in C15): nothing of
        # T.Message is shown, so every one of them is a site without an output.
        callers = {"core/WishlistController.lua": (b"Nexus.UserText.Message(message)",),
                   READOUT: (b"Nexus.UserText.Message(model.text)",),
                   PANEL: (b"userText.Message(raw)", b"Nexus.UserText.Message(reason)"),
                   "ui/JournalTab.lua": (b"Nexus.UserText.Message(text)",),
                   "core/Main.lua": (b"Nexus.UserText.Message(msg)",)}
        changed = dict(self.files)
        for path, needles in callers.items():
            for needle in needles:
                changed[path] = edit(changed[path], needle,
                                     needle.replace(b".Message(", b".MessageDisconnected("))
        receipt, rows, bindings, other = judged(changed)
        self.assertEqual(bindings, dict.fromkeys(every, "UNBOUND"))
        chain = map_chain(self, receipt, "SeamReason")
        self.assertEqual((chain["established"], chain["wrapperReturnsResult"], chain["boundKeys"]),
                         (False, True, []))
        for key in MESSAGE_KEYS:
            with self.subTest(disconnected=key):
                self.assertEqual(here(rows, key, "sites"), [])
                self.assertEqual([(site["site"], site["reason"])
                                  for site in here(rows, key, "unprovenSites")],
                                 [("wrapper-call", "output-not-reached")])
        self.assertEqual({(site["site"], site["reason"]) for key in REASON_KEYS
                          for site in here(rows, key, "unprovenSites")},
                         {("map-value", "output-not-reached")})
        # The accessor can return another table: it names no seam, so none
        # of the three functions is a wrapper and nothing here is a site.
        accessor = (b'    if type(localization)=="table" and type(localization.Text)=="function" '
                    b'then return localization end\n    return nil\nend\n')
        receipt, rows, bindings, other = judged(with_file(self.files, USER_TEXT, edit(
            user, accessor, accessor.replace(b"return nil", b"return {}"))))
        self.assertEqual(bindings, dict.fromkeys(every, "UNBOUND"))
        self.assertEqual(other, [])
        self.assertEqual([chain["wrapper"]["name"] for chain in receipt["mapChains"]],
                         ["LocalizedReason"])
        for key in every:
            with self.subTest(no_site=key):
                self.assertEqual(here(rows, key, "sites") + here(rows, key, "unprovenSites"), [])
        # The guard table has a code its map lacks (SeamReason would get nil
        # as its key): the dispatch is unresolved by name, the map's keys are
        # unbound, and the literal wrapper calls are untouched.
        guard = edit(user, b"local reasons={\n",
                     b'local reasons={\n    ["SPEC_ONLY_IN_GUARD"]="Spec guard only",\n')
        receipt, rows, bindings, other = judged(with_file(self.files, USER_TEXT, guard))
        self.assertEqual(bindings, dict(bound, **dict.fromkeys(REASON_KEYS, "UNBOUND")))
        self.assertEqual(other, [(
            USER_TEXT, line_of(guard, b"SeamReason(reasonKeys[s],reasons[s])"), "dispatch",
            "reasons is not a read-only local table of literal strings with exactly the keys "
            "of reasonKeys")])
        self.assertEqual([chain["wrapper"]["name"] for chain in receipt["mapChains"]],
                         ["LocalizedReason"])

    def test_c37_a_seam_accessor_names_the_seam_only_in_its_exact_shape(self):
        # R1 on the C26 host: a local function without parameters whose every
        # return is nil or the seam itself (one of them the seam), called
        # without an argument, names the seam; a local declared with that
        # call is a receiver like a local alias. One receipt: each case on
        # its own line in its own do block, judged by its own site. A case
        # is "bound" (a proved site), "unproven" (a site without an output)
        # or None (no site at all), with the unresolved construct it names.
        key = "panel.heading.progress"
        host = "core/SessionPause.lua"
        acc = (b'local function A() local l=Nexus.Localization if type(l)=="table" then '
               b'return l end return nil end ')
        show = b'local l=A() specLabel:SetText(l.Text("panel.heading.progress"))'
        plain = b'local function A() return Nexus.Localization end '
        cases = (
            ("a direct call on a local fetched through the accessor", acc + show, "bound", None),
            ("the accessor called in place",
             acc + b'specLabel:SetText(A().Text("panel.heading.progress"))', "bound", None),
            ("an accessor declared as a local function value",
             b'local A=function() return Nexus.Localization end ' + show, "bound", None),
            ("a wrapper that fetches through the accessor",
             acc + b'local function W(key) local l=A() if l then local text=l.Text(key) '
             b'return text end return "x" end specLabel:SetText(W("panel.heading.progress"))',
             "bound", None),
            ("the real shape: two type checks, text and source, the English otherwise",
             b'local function A() local l=Nexus.Localization if type(l)=="table" and '
             b'type(l.Text)=="function" then return l end return nil end '
             b'local function W(key,english) local l=A() if l then local text,source='
             b'l.Text(key) if type(text)=="string" and source~="unavailable" then return text '
             b'end end return english end '
             b'specLabel:SetText(W("panel.heading.progress","Progress"))', "bound", None),
            ("a wrapper that fetches through the accessor and discards the result",
             acc + b'local function W(key) local l=A() if l then l.Text(key) end return "x" end '
             b'specLabel:SetText(W("panel.heading.progress"))', "unproven", None),
            ("a result that is never shown",
             acc + b'local l=A() local unused=l.Text("panel.heading.progress") '
             b'specLabel:SetText("x")', "unproven", None),
            ("an accessor that returns only nil",
             b'local function A() return nil end ' + show, None, None),
            ("one return of a fresh table",
             b'local function A() local l=Nexus.Localization if l then return l end '
             b'return {} end ' + show, None, None),
            ("one return of another module",
             b'local function A() if Nexus.Other then return Nexus.Other end '
             b'return Nexus.Localization end ' + show, None, None),
            ("the seam or a fresh table",
             b'local function A() return Nexus.Localization or {} end ' + show, None, None),
            ("a return of two values",
             b'local function A() return Nexus.Localization, 1 end ' + show, None, None),
            ("a return without a value",
             b'local function A() if not Nexus.Localization then return end '
             b'return Nexus.Localization end ' + show, None, None),
            ("a body that can run off its end",
             b'local function A() if Nexus.Localization then return Nexus.Localization end end '
             + show, None, None),
            ("an accessor with a parameter",
             b'local function A(x) return Nexus.Localization end ' + show, None, None),
            ("an accessor with ...",
             b'local function A(...) return Nexus.Localization end ' + show, None, None),
            ("an accessor called with an argument",
             plain + b'local l=A(1) specLabel:SetText(l.Text("panel.heading.progress"))',
             None, None),
            ("an accessor with a nested function",
             b'local function A() local f=function() end return Nexus.Localization end ' + show,
             None, None),
            ("an accessor that returns another accessor's call",
             plain + b'local function B() return A() end local l=B() '
             b'specLabel:SetText(l.Text("panel.heading.progress"))', None, None),
            ("an accessor that returns its own call",
             b'local function A() return A() end ' + show, None, None),
            ("an accessor that returns a local declared with an accessor call",
             plain + b'local function B() local l=A() return l end local l=B() '
             b'specLabel:SetText(l.Text("panel.heading.progress"))', None, None),
            ("a global function of the same shape",
             b'function SpecGlobalAccessor() return Nexus.Localization end '
             b'local l=SpecGlobalAccessor() specLabel:SetText(l.Text("panel.heading.progress"))',
             None, None),
            ("a local declared first and given the function later",
             b'local A A=function() return Nexus.Localization end ' + show, None, None),
            ("a shadowing local function that returns a fresh table",
             acc + b'do local function A() return {Text=tostring} end ' + show + b' end',
             None, None),
            ("the fetched local as the second name of the declaration",
             acc + b'local a,l=A() specLabel:SetText(l.Text("panel.heading.progress"))',
             None, None),
            ("the accessor assigned again",
             plain + b'A=function() return {Text=tostring} end ' + show, None, "alias"),
            ("the fetched local assigned again",
             acc + b'local l=A() l={Text=tostring} '
             b'specLabel:SetText(l.Text("panel.heading.progress"))', None, "alias"),
            ("the accessor's inner alias assigned before its return",
             b'local function A() local l=Nexus.Localization l={Text=tostring} return l end '
             + show, None, "alias"),
            ("a method call on the fetched local",
             acc + b'local l=A() specLabel:SetText(l:Text("panel.heading.progress"))',
             None, "method-call"),
            ("a method call on the accessor call",
             acc + b'specLabel:SetText(A():Text("panel.heading.progress"))', None, "method-call"),
            ("the consumer method read through the accessor without being called",
             acc + b'local f=A().Text specLabel:SetText(f("panel.heading.progress"))',
             None, "indirect-key-method"),
        )
        first = (self.files[host] + V15_LABEL).count(b"\n") + 1
        code = b"\n".join(b"do " + case + b" end" for _, case, _, _ in cases)
        receipt = self.receipt(self.hosted(code))
        row = self.binding(receipt, key)
        proved = {site["line"] for site in row["sites"] if site["outputs"]}
        unproven = {site["line"] for site in row["unprovenSites"]}
        constructs = {}
        for problem in receipt["problems"]:
            if problem["code"] != "binding-unbound":
                self.assertEqual((problem["code"], problem["path"]), ("binding-unresolved", host))
                constructs.setdefault(problem["line"], set()).add(problem["construct"])
        for line, (name, _, state, construct) in enumerate(cases, first):
            with self.subTest(case=name):
                self.assertEqual((line in proved, line in unproven),
                                 (state == "bound", state == "unproven"))
                self.assertEqual(constructs.get(line, set()), {construct} if construct else set())
        # A write of the seam is never hidden behind an accessor: through
        # the fetched local, and inside the accessor itself. One receipt.
        writes = (
            acc + b'local l=A() l.Text=tostring '
            b'specLabel:SetText(l.Text("panel.heading.progress"))',
            b'local function A() Nexus.Localization={Text=tostring} return Nexus.Localization end '
            + show)
        receipt = self.gate_fails(self.hosted(b"\n".join(b"do " + case + b" end"
                                                         for case in writes)))
        self.assertEqual([(problem["code"], problem["path"], problem["line"], problem["construct"])
                          for problem in receipt["problems"]
                          if problem["code"] != "binding-unbound"],
                         [("binding-mutation", host, first, "seam-assignment"),
                          ("binding-mutation", host, first + 1, "seam-assignment")])

    def test_c38_a_dispatch_guarded_by_a_parallel_table_needs_exactly_the_maps_keys(self):
        # R2 on a module appended to the real core/SessionPause.lua: the
        # guard of "if GUARD[v] then return wrapper(MAP[v]) end" may index a
        # second read-only local table of literal strings with exactly MAP's
        # keys. One receipt: each case is one line with its own map, guard,
        # dispatcher and caller, judged by its own chain or its own problem.
        host, key = "core/SessionPause.lua", "panel.heading.progress"
        head = (
            b'local SpecT = {}',
            b'Nexus.SpecDispatch = SpecT',
            b'local function SpecW(key) local l=Nexus.Localization return l.Text(key) end',
            b'local function SpecSeam() local l=Nexus.Localization if type(l)=="table" then '
            b'return l end return nil end',
            b'local function SpecV(key) local l=SpecSeam() if l then local text=l.Text(key) '
            b'return text end return "x" end',
        )
        pairs_of = b'{["A"]="panel.heading.progress",["B"]="panel.heading.progress"}'
        guarded = b'{["A"]="one",["B"]="two"}'
        function = (b'function SpecT.D#(v) if specGuard#[v] then return SpecW(specMap#[v]) end '
                    b'return v end')
        shown = b'DEFAULT_CHAT_FRAME:AddMessage(Nexus.SpecDispatch.D#("A"))'
        same = "the call is not the sole return guarded by the same MAP[v]"
        keys = "specGuard# is not a read-only local table of literal strings with exactly the " \
               "keys of specMap#"
        cases = (
            # (name, guard table, function, statements after it, caller, expectation)
            # expectation: (established, shadowed codes) of its chain, or the
            # detail of its unresolved dispatch.
            ("a parallel guard with exactly the map's keys", guarded, function, b'', shown,
             (True, [])),
            ("the same through a seam accessor wrapper", guarded,
             function.replace(b"SpecW(", b"SpecV("), b'', shown, (True, [])),
            ("the map itself as the guard", guarded,
             function.replace(b"if specGuard#[v]", b"if specMap#[v]"), b'', shown, (True, [])),
            ("a parallel guard that a for-in pairs header reads", guarded, function,
             b'for code in pairs(specGuard#) do end', shown, (True, [])),
            ("an entry shadowed by an earlier guard, the other shown", guarded,
             b'local specOther#={["A"]="shadow"} ' + function.replace(
                 b"(v) if", b"(v) if specOther#[v] then return v end if"),
             b'', shown.replace(b'"A"', b'"B"'), (True, ["A"])),
            ("the result discarded by its only caller", guarded, function, b'',
             b'local specUnused#=Nexus.SpecDispatch.D#("A")', (False, [])),
            ("shown only by a call of another dispatcher", guarded, function, b'',
             b'DEFAULT_CHAT_FRAME:AddMessage(Nexus.SpecDispatch.D1("A")) '
             b'local specUnused#=Nexus.SpecDispatch.D#("A")', (False, [])),
            ("a guard key the map lacks", b'{["A"]="one",["B"]="two",["C"]="three"}', function,
             b'', shown, keys),
            ("a map key the guard lacks", b'{["A"]="one"}', function, b'', shown, keys),
            ("a guard value false", b'{["A"]=false,["B"]="two"}', function, b'', shown, keys),
            ("a guard value that is a number", b'{["A"]=1,["B"]="two"}', function, b'', shown,
             keys),
            ("a guard value that is no literal", b'{["A"]=tostring(1),["B"]="two"}', function,
             b'', shown, keys),
            ("a guard with a positional entry", b'{"one",["A"]="one",["B"]="two"}', function,
             b'', shown, keys),
            ("the guard assigned again", guarded, function, b'specGuard#={}', shown, keys),
            ("the guard passed to a function", guarded, function, b'tostring(specGuard#)',
             shown, keys),
            ("the guard written through", guarded, function, b'specGuard#.C="three"', shown,
             keys),
            ("the guard stored in a table", guarded, function,
             b'local specBox#={specGuard#}', shown, keys),
            ("a guard that is no local table", guarded,
             function.replace(b"if specGuard#[v]", b"if SpecGlobalGuard[v]"), b'', shown, same),
            ("a guard over another variable", guarded,
             function.replace(b"(v) if specGuard#[v]", b"(v,w) if specGuard#[w]"), b'', shown,
             same),
            ("the call is not the guard's return", guarded,
             function.replace(b"then return SpecW(specMap#[v]) end",
                              b"then local t=SpecW(specMap#[v]) return t end"), b'', shown, same),
            ("the variable assigned before the dispatch", guarded,
             function.replace(b"(v) if", b"(v) v=tostring(v) if"), b'', shown,
             "the dispatch variable is not a local of this function left unassigned up to "
             "the dispatch"),
            ("an earlier statement that can return first", guarded,
             function.replace(b"(v) if", b'(v) if v=="x" then return v end if'), b'', shown,
             "an earlier statement at line %d can return first"),
        )
        prefix = self.files[host] + b"\n" + b"\n".join(head) + b"\n"
        first = prefix.count(b"\n") + 1
        lines = []
        for number, (_, guard, body, after, caller, _) in enumerate(cases, 1):
            text = b" ".join(part for part in (
                b"local specMap#=" + pairs_of, b"local specGuard#=" + guard, body, after, caller)
                if part)
            lines.append(text.replace(b"#", str(number).encode()))
        receipt = self.receipt(with_file(self.files, host, prefix + b"\n".join(lines) + b"\n"))
        chains = {chain["dispatch"]["line"]: chain for chain in receipt["mapChains"]
                  if chain["dispatch"]["path"] == host}
        problems = {}
        for problem in receipt["problems"]:
            if problem["code"] != "binding-unbound":
                self.assertEqual((problem["code"], problem["path"], problem["construct"]),
                                 ("binding-unresolved", host, "dispatch"))
                problems.setdefault(problem["line"], []).append(problem["detail"])
        for number, (name, _, _, _, _, expected) in enumerate(cases, 1):
            line = first + number - 1
            with self.subTest(case=name):
                if type(expected) is tuple:
                    self.assertNotIn(line, problems)
                    self.assertIn(line, chains)
                    chain = chains[line]
                    self.assertEqual(
                        (chain["map"]["name"], chain["dispatcher"], chain["entries"],
                         chain["wrapperReturnsResult"]),
                        ("specMap%d" % number, "Nexus.SpecDispatch.D%d" % number, 2, True))
                    self.assertEqual(
                        (chain["established"], chain["boundKeys"],
                         [entry["code"] for entry in chain["shadowedEntries"]]),
                        (expected[0], [key] if expected[0] else [], expected[1]))
                    self.assertEqual(bool(chain["outputs"]), expected[0])
                else:
                    self.assertNotIn(line, chains)
                    detail = expected.replace("#", str(number))
                    self.assertEqual(problems.get(line),
                                     [detail % line if "%d" in detail else detail])
        # The real chains are as they were beside the appended module.
        self.assertEqual(sorted(map_chain(self, receipt, "SeamReason")["boundKeys"]),
                         sorted(REASON_KEYS))
        # A parallel guard read by pairs needs the global pairs unassigned,
        # like every guard table read that way (the real reasons table too).
        iterated = lines[3] + b" pairs = pairs"
        receipt = self.receipt(with_file(self.files, host, prefix + iterated + b"\n"))
        self.assertEqual([chain for chain in receipt["mapChains"]
                          if chain["dispatch"]["path"] == host], [])
        refused = "a guard table is iterated by pairs, which the loaded source assigns"
        self.assertEqual(sorted((problem["path"], problem["line"], problem["construct"],
                                 problem["detail"])
                                for problem in receipt["problems"]
                                if problem["code"] != "binding-unbound"),
                         sorted([(host, first, "dispatcher", refused)]
                                + [(USER_TEXT, line, "dispatcher", refused) for line in (
                                    self.dispatch_line(b"SeamReason(reasonKeys[s],reasons[s])"),
                                    self.dispatch_line(
                                        b"LocalizedReason(localizedReasons[s],s)"))]))


if __name__ == "__main__":
    unittest.main()
