Module: hello

format-out("Hello from Dylan — running in your browser via wasm64!\n");
format-out("Open Dylan compiled to wasm64. Runtime, GC, dispatch, NLX — live.\n\n");

// ---------- factorial ----------
define function fact (n :: <integer>) => (r :: <integer>)
  if (n <= 1) 1 else n * fact(n - 1) end
end;
format-out("factorial(5)  = %d\n",   fact(5));
format-out("factorial(10) = %d\n",   fact(10));
format-out("factorial(12) = %d\n\n", fact(12));

// ---------- fibonacci ----------
define function fib (n :: <integer>) => (r :: <integer>)
  if (n < 2) n else fib(n - 1) + fib(n - 2) end
end;
format-out("fib(10) = %d\n",   fib(10));
format-out("fib(15) = %d\n\n", fib(15));

// ---------- integer-to-string (uses block/return internally; needs working NLX) ----------
format-out("integer-to-string(12345) = ");
format-out(integer-to-string(12345));
format-out("\n");
format-out("integer-to-string(-42)   = ");
format-out(integer-to-string(-42));
format-out("\n\n");

// ---------- in-place sort (uses NLX via for-loop iteration protocol) ----------
define function sort! (v :: <vector>) => ()
  let n :: <integer> = v.size;
  for (i :: <integer> from 0 below n - 1)
    for (j :: <integer> from i + 1 below n)
      if (v[j] < v[i])
        let t = v[i];
        v[i] := v[j];
        v[j] := t;
      end if;
    end for;
  end for;
end;
let nums = vector(5, 3, 8, 1, 9, 2, 7, 4, 6);
format-out("before sort: ");
for (x in nums) format-out("%d ", x); end for;
format-out("\n");
sort!(nums);
format-out("after sort:  ");
for (x in nums) format-out("%d ", x); end for;
format-out("\n\n");

// ---------- upstream Open Dylan towers-of-hanoi example (verbatim) -----
// from opendylan/sources/examples/console/towers-of-hanoi/
//   – classes with required-init-keyword slots
//   – `<deque>` push/pop, `map`, `range`, generic methods with #key,
//     next-method, *n-operations* module variable.
define class <disk> (<object>)
  constant slot diameter :: <integer>, required-init-keyword: diameter:;
end class <disk>;
define function make-disk (integer :: <integer>) => (disk :: <disk>)
  make(<disk>, diameter: integer)
end function make-disk;

define class <tower> (<object>)
  constant slot name :: <string>, required-init-keyword: name:;
  constant slot disks :: <deque> = make(<deque>);
end class <tower>;
define method initialize
    (tower :: <tower>, #key initial-disks :: <sequence> = #[]) => ()
  next-method();
  for (disk in initial-disks)
    push(tower.disks, disk)
  end
end method initialize;
define method height (tower :: <tower>) => (height :: <integer>)
  size(tower.disks)
end method height;

define variable *n-operations* :: <integer> = 0;

define method move-disk (from-tower :: <tower>, to-tower :: <tower>)
  *n-operations* := *n-operations* + 1;
  format-out(".");
  let disk = pop(from-tower.disks);
  push(to-tower.disks, disk)
end method move-disk;

define method hanoi-towers
    (from-tower :: <tower>, to-tower :: <tower>, with-tower :: <tower>,
     #key count :: <integer> = from-tower.height) => ()
  if (count >= 1)
    hanoi-towers(from-tower, with-tower, to-tower, count: count - 1);
    move-disk(from-tower, to-tower);
    hanoi-towers(with-tower, to-tower, from-tower, count: count - 1)
  end
end method hanoi-towers;

define method print-tower (tower :: <tower>) => ()
  for (disk :: <disk> in tower.disks, separator = "" then ", ")
    format-out("%s%d", separator, disk.diameter)
  end
end method print-tower;

define method print-towers (#rest towers :: <tower>) => ()
  for (tower :: <tower> in towers)
    format-out("  %s: ", tower.name);
    print-tower(tower);
    format-out("\n")
  end;
  format-out("\n")
end method print-towers;

define method play-hanoi (height :: <integer>) => ()
  format-out("Upstream Towers of Hanoi (5 disks, deque-based):\n\n");
  let disks = map(make-disk, range(from: 1, to: height));
  let left-tower   = make(<tower>, name: "Left",   initial-disks: disks);
  let middle-tower = make(<tower>, name: "Middle");
  let right-tower  = make(<tower>, name: "Right");
  format-out("Initial position:\n");
  print-towers(left-tower, middle-tower, right-tower);
  hanoi-towers(left-tower, middle-tower, right-tower);
  format-out("took %d operations\n\nFinal position:\n", *n-operations*);
  print-towers(left-tower, middle-tower, right-tower)
end method play-hanoi;

play-hanoi(5);

force-out();
