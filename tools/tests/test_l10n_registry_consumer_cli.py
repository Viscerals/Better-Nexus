"""Registry-bound localization catalog, S8: --consumers on the repository and on
confined roots, _children on directly made syntax-tree nodes, and the digest-cache and
parse-memo byte bounds (Refs #147).

Split from the single registry test file (SPLIT-PLAN.md): its classes are copied
verbatim; shared names come from tools/tests/l10n_registry_support.py. Synthetic offline
evidence only: no Lua runs, and this is not fluent, human or native evidence. Python 3.9+,
standard library only. Registered in PYTHON_TESTS of tools/run_prototype_tests.py.

Run directly:  python tools/tests/test_l10n_registry_consumer_cli.py -v
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


class ChildrenTests(unittest.TestCase):
    """_children (the direct children of one syntax-tree node) on nodes made
    directly with the tool's _Node: each branch kind gives its children in
    source order as a new list; every other kind gives a new empty list; a
    kind that is not an exact str goes through the branches as it always
    did; and the fixed set of branch kinds (_CHILD_KINDS) is the set the
    branches themselves compare against, read from the tool's source. No
    input file is parsed and no receipt is made."""

    @classmethod
    def setUpClass(cls):
        cls.tool = s8_catalog()
        cls.module_tree = ast.parse(inspect.getsource(cls.tool))
        cls.at = type("At", (), {"line": 1, "column": 1})()

    def node(self, kind, **fields):
        return self.tool._Node(kind, self.at, **fields)

    def branch_comparisons(self):
        """(the kind strings _children's branches test with == or in, every
        other comparison of kind there as (operator, target source))."""
        function = next(item for item in self.module_tree.body
                        if isinstance(item, ast.FunctionDef) and item.name == "_children")
        kinds, others = set(), []
        for item in ast.walk(function):
            if not (isinstance(item, ast.Compare) and isinstance(item.left, ast.Name)
                    and item.left.id == "kind"):
                continue
            self.assertEqual(len(item.ops), 1, ast.dump(item))
            operator, target = item.ops[0], item.comparators[0]
            if isinstance(operator, ast.Eq) and isinstance(target, ast.Constant):
                kinds.add(target.value)
            elif isinstance(operator, ast.In) and isinstance(target, ast.Tuple):
                for element in target.elts:
                    self.assertIsInstance(element, ast.Constant, ast.dump(item))
                    kinds.add(element.value)
            else:
                others.append((type(operator).__name__, ast.unparse(target)))
        return kinds, others

    def created_kinds(self):
        """Every kind the tool's source gives _Node as a literal first argument."""
        return {item.args[0].value for item in ast.walk(self.module_tree)
                if isinstance(item, ast.Call) and isinstance(item.func, ast.Name)
                and item.func.id == "_Node" and item.args
                and isinstance(item.args[0], ast.Constant) and type(item.args[0].value) is str}

    def ids(self, values):
        return [id(value) for value in values]

    def test_the_fixed_branch_kinds_are_the_kinds_the_branches_compare(self):
        kinds, others = self.branch_comparisons()
        self.assertTrue(all(type(kind) is str for kind in kinds), kinds)
        self.assertEqual(len(kinds), 19)
        self.assertIs(type(self.tool._CHILD_KINDS), frozenset)
        self.assertEqual(kinds, set(self.tool._CHILD_KINDS))
        # The only other comparison of kind is the early exit on that set.
        self.assertEqual(others, [("NotIn", "_CHILD_KINDS")])
        # Every branch kind is one the parser or the flow creates.
        self.assertLessEqual(kinds, self.created_kinds())

    def test_every_other_kind_gives_a_new_empty_list(self):
        # The leaf kinds are read from the tool's own _Node constructors.
        leaves = self.created_kinds() - self.branch_comparisons()[0]
        self.assertTrue({"name", "string", "constant"} <= leaves, sorted(leaves))
        for kind in sorted(leaves) + ["not-a-kind", ""]:
            with self.subTest(kind=kind):
                item = self.node(kind)
                first, second = self.tool._children(item), self.tool._children(item)
                self.assertEqual((type(first), first, type(second), second), (list, [], list, []))
                self.assertIsNot(first, second)
                first.append(object())
                self.assertEqual(self.tool._children(item), [])

    def test_each_branch_kind_gives_its_children_in_order_as_a_new_list(self):
        o = [object() for _ in range(6)]
        node = self.node
        fields = [node("field", key=o[0], value=o[1]), node("field", key=None, value=o[2])]
        cases = (
            ("local", node("local", exprs=[o[0], o[1]]), [o[0], o[1]]),
            ("return", node("return", exprs=[o[0]]), [o[0]]),
            ("return without a value", node("return", exprs=[]), []),
            ("localfunction", node("localfunction", func=o[0]), [o[0]]),
            ("funcstat", node("funcstat", target=o[0], func=o[1]), [o[0], o[1]]),
            ("assign", node("assign", targets=[o[0], o[1]], exprs=[o[2]]), [o[0], o[1], o[2]]),
            ("callstat", node("callstat", call=o[0]), [o[0]]),
            ("do", node("do", body=[o[0], o[1]]), [o[0], o[1]]),
            ("function", node("function", body=[o[0]]), [o[0]]),
            ("while", node("while", cond=o[0], body=[o[1], o[2]]), [o[0], o[1], o[2]]),
            ("repeat", node("repeat", body=[o[0], o[1]], cond=o[2]), [o[0], o[1], o[2]]),
            ("if with elseif and else",
             node("if", clauses=[(o[0], [o[1], o[2]]), (o[3], [o[4]])], orelse=[o[5]]),
             [o[0], o[1], o[2], o[3], o[4], o[5]]),
            ("if without else", node("if", clauses=[(o[0], [o[1]])], orelse=None), [o[0], o[1]]),
            ("fornum with a step", node("fornum", start=o[0], stop=o[1], step=o[2], body=[o[3]]),
             [o[0], o[1], o[2], o[3]]),
            ("fornum without a step",
             node("fornum", start=o[0], stop=o[1], step=None, body=[o[3]]), [o[0], o[1], o[3]]),
            ("forin", node("forin", exprs=[o[0]], body=[o[1], o[2]]), [o[0], o[1], o[2]]),
            ("call", node("call", func=o[0], args=[o[1], o[2]]), [o[0], o[1], o[2]]),
            ("method", node("method", obj=o[0], args=[o[1]]), [o[0], o[1]]),
            ("index", node("index", obj=o[0], key=o[1]), [o[0], o[1]]),
            ("paren", node("paren", expr=o[0]), [o[0]]),
            ("operation", node("operation", operands=[o[0], o[1], o[2]]), [o[0], o[1], o[2]]),
            ("table with a keyed and a positional field", node("table", fields=fields),
             [o[0], o[1], o[2]]),
        )
        covered = set()
        for name, item, expected in cases:
            with self.subTest(case=name):
                covered.add(item.kind)
                inputs = [getattr(item, slot) for slot in item.__slots__
                          if hasattr(item, slot) and type(getattr(item, slot)) is list]
                before = [list(value) for value in inputs]
                result = self.tool._children(item)
                self.assertIs(type(result), list)
                self.assertEqual(self.ids(result), self.ids(expected))
                self.assertIsNot(result, self.tool._children(item))
                for value in inputs:
                    self.assertIsNot(result, value)
                result.append(object())
                self.assertEqual([list(value) for value in inputs], before)
                self.assertEqual(self.ids(self.tool._children(item)), self.ids(expected))
        self.assertEqual(covered, self.branch_comparisons()[0])

    def test_a_kind_that_is_not_an_exact_str_goes_through_the_branches(self):
        class Plain(str):
            pass

        class CallLike(str):
            # Unhashable, and equal to "call" whatever its own text: with a
            # leaf's text it still takes the call branch, as it always did.
            __hash__ = None

            def __eq__(self, other):
                return other == "call" or str.__eq__(self, other)

        o = [object() for _ in range(3)]
        cases = (
            ("an ordinary str subclass naming call",
             self.node(Plain("call"), func=o[0], args=[o[1], o[2]]), [o[0], o[1], o[2]]),
            ("an ordinary str subclass naming a leaf", self.node(Plain("name")), []),
            ("an unhashable str subclass equal to call with a leaf's text",
             self.node(CallLike("name"), func=o[0], args=[o[1]]), [o[0], o[1]]),
            ("a kind that is not a str", self.node(None), []),
        )
        for name, item, expected in cases:
            with self.subTest(case=name):
                result = self.tool._children(item)
                self.assertIs(type(result), list)
                self.assertEqual(self.ids(result), self.ids(expected))


class StateBoundTests(unittest.TestCase):
    """STD-V15-3: an input larger than the digest cache or the parse memo
    byte bound is processed with the same result but never kept, and evicts
    nothing kept before it. A fresh tool, so no other test's memo moves."""

    def test_oversized_inputs_are_never_retained(self):
        catalog = load_catalog()
        small = b"Nexus = Nexus or {}\nNexus.LocalizationEnglish = {}\n"
        self.assertEqual(catalog.parse_english(small), {})
        kept = dict(catalog._DIGESTS)
        oversized = b"\xff" + b" " * catalog._DIGESTS_BYTES
        with self.assertRaises(catalog.CatalogSyntaxError) as raised:
            catalog.parse_english(oversized)
        self.assertEqual(raised.exception.code, "not-utf8")
        self.assertEqual(catalog._digest(oversized),
                         hashlib.sha256(oversized).digest())
        self.assertEqual(catalog._DIGESTS, kept)
        self.assertLessEqual(sum(map(len, catalog._DIGESTS)), catalog._DIGESTS_BYTES)
        # The parse memo: the same refusal result, not kept; the file kept
        # before it stays.
        lua = b"local x = 1\n"
        first = catalog._parsed(lua)
        memo = dict(catalog._PARSE_MEMO)
        big = b"\xff" + b" " * catalog._PARSE_MEMO_BYTES
        self.assertEqual(catalog._parsed(big)[1], {"code": "not-utf8"})
        self.assertEqual(catalog._PARSE_MEMO, memo)
        self.assertLessEqual(sum(catalog._PARSE_MEMO_SIZES.values()), catalog._PARSE_MEMO_BYTES)
        self.assertIs(catalog._parsed(lua), first)


class ConsumerCommandLineTests(unittest.TestCase):
    """S8: --consumers reads both TOCs and every Lua file they load from the
    confined root and prints one consumers record; the earlier modes are
    unchanged."""

    def run_process(self, *args):
        return subprocess.run([sys.executable, "-B", str(CATALOG_TOOL), *[str(a) for a in args]],
                              capture_output=True, cwd=str(ROOT))

    def run_cli(self, *args):
        """main() of the shared loaded tool in this process, with the exact
        stdout and stderr bytes it writes; one real process run is kept in
        test_repository_root, and the parse memo keeps the rest within the
        registered time budget."""
        import io
        out, err = io.TextIOWrapper(io.BytesIO()), io.TextIOWrapper(io.BytesIO())
        saved = sys.stdout, sys.stderr
        sys.stdout, sys.stderr = out, err
        try:
            code = s8_catalog().main([str(arg) for arg in args])
        finally:
            sys.stdout, sys.stderr = saved
        return subprocess.CompletedProcess(args, code, out.buffer.getvalue(),
                                           err.buffer.getvalue())

    def copy_root(self, root, files):
        for relative, value in files.items():
            target = root.joinpath(*relative.split("/"))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)

    def test_repository_root(self):
        # main() on the actual repository root (named explicitly, so the
        # result never depends on where the tool file lives) reads both TOCs
        # and all 100 loaded files itself and writes exactly the API receipt,
        # with the exit status the documented --consumers contract gives that
        # receipt: 2 while it is not valid; else 0, or 1 with
        # --require-complete (completeness is never established). The
        # receipt's validity is taken from the independent API call on the
        # same bytes, never from the command line. This checks the command
        # line's status and serialization only. Whether the repository's
        # receipt is valid at all is the registered gate (C2), which stays
        # strict: the current receipt is invalid, so exit 2 is expected here
        # while C2 fails.
        expected = s8_catalog().consumer_binding_report(*binding_args(s8_files()))
        valid = expected["valid"]
        self.assertIs(type(valid), bool)
        self.assertIs(valid, not expected["problems"])
        status, held_status = (0, 1) if valid else (2, 2)
        shown = json.loads(json.dumps(expected))
        run = self.run_cli("--root", ROOT, "--consumers")
        self.assertEqual((run.returncode, run.stderr), (status, b""))
        record = json.loads(run.stdout)
        self.assertEqual((record["record"], record["exitCode"], record["requireComplete"]),
                         ("consumers", status, "not_requested"))
        self.assertEqual(record["consumers"], shown)
        self.assertEqual(len(record["consumers"]["sources"]), 100)
        # A real process on a small confined root: the same entry point, exit
        # status and one record, with unbound keys there (exit 2).
        files = s8_files()
        small = {path: files[path] for path in INPUTS + CONSUMER_TOCS[1:]
                 + ("companion/NexusSupport/Storage.lua",)}
        small["Nexus.toc"] = b"".join(line for line in files["Nexus.toc"].splitlines(True)
                                      if b"Localization" in line or line.startswith(b"#"))
        with tempfile.TemporaryDirectory() as temp:
            self.copy_root(Path(temp), small)
            process = self.run_process("--root", temp, "--consumers")
            self.assertEqual((process.returncode, process.stderr), (2, b""))
            self.assertEqual(process.stdout, self.run_cli("--root", temp, "--consumers").stdout)
            receipt = json.loads(process.stdout)["consumers"]
            self.assertEqual((len(receipt["sources"]), receipt["counts"]["UNBOUND"]),
                             (4, CURRENT_FULL_UI_KEYS))
        # --require-complete on the same root: the same receipt, the status
        # the contract gives it (1 only for a valid receipt, 2 while invalid).
        held = self.run_cli("--root", ROOT, "--consumers", "--require-complete")
        held_record = json.loads(held.stdout)
        self.assertEqual((held.returncode, held.stderr, held_record["exitCode"],
                          held_record["requireComplete"]),
                         (held_status, b"", held_status, "requested"))
        self.assertEqual(held_record["consumers"], shown)
        for args, code in ((("--consumers", "--consumers"), "argument-duplicate"),
                           (("--consumers", "--diagnose"), "argument-conflict"),
                           (("--provenance", "--consumers"), "argument-conflict")):
            with self.subTest(args=args):
                run = self.run_cli(*args)
                self.assertEqual((run.returncode, run.stdout), (2, b""))
                self.assertEqual(json.loads(run.stderr)["code"], code)

    def test_mutated_root_fails_only_in_consumers_mode(self):
        # On the cohort substrate (see cohort_view), whose own receipt already
        # leaves other keys unbound: the mutation adds exactly one problem.
        files = s8_cohort_files()
        base = s8_catalog().consumer_binding_report(*binding_args(files))["problems"]
        files[PANEL] = edit(files[PANEL], PROGRESS_CALL, PROGRESS_FAKES)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.copy_root(root, files)
            before = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            run = self.run_cli("--root", root, "--consumers")
            self.assertEqual((run.returncode, run.stderr), (2, b""))
            receipt = json.loads(run.stdout)["consumers"]
            self.assertIs(receipt["valid"], False)
            base = json.loads(json.dumps(base))
            self.assertEqual([(problem["code"], problem.get("key")) for problem in receipt["problems"]
                              if problem not in base], [("binding-unbound", "panel.heading.progress")])
            self.assertEqual([problem for problem in base if problem not in receipt["problems"]], [])
            for args in ((), ("--registry",), ("--diagnose",), ("--provenance",)):
                with self.subTest(args=args):
                    self.assertEqual(self.run_cli("--root", root, *args).returncode, 0)
            after = {path: path.read_bytes() for path in root.rglob("*") if path.is_file()}
            self.assertEqual(after, before)

    def test_unsafe_or_missing_listed_source_fails(self):
        files = s8_files()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "repo"
            self.copy_root(root, files)
            (Path(temp) / "outside.lua").write_bytes(b"local x = 1\n")
            toc = root / "Nexus.toc"
            toc.write_bytes(edit(files["Nexus.toc"], b"core\\Main.lua\n",
                                 b"core\\Main.lua\n..\\outside.lua\n"))
            run = self.run_cli("--root", root, "--consumers")
            self.assertEqual((run.returncode, run.stdout), (2, b""))
            error = json.loads(run.stderr)
            self.assertEqual((error["code"], error["subject"]), ("consumer-toc-entry", "Nexus.toc"))
            toc.write_bytes(files["Nexus.toc"])
            (root / "ui" / "Readout.lua").unlink()
            run = self.run_cli("--root", root, "--consumers")
            self.assertEqual((run.returncode, run.stdout), (2, b""))
            error = json.loads(run.stderr)
            self.assertEqual((error["code"], error["subject"]), ("input-missing", READOUT))


if __name__ == "__main__":
    unittest.main()
