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

// ---------- towers of hanoi ----------
define function hanoi
    (n :: <integer>, from :: <string>, to :: <string>, via :: <string>) => ()
  if (n = 1)
    format-out("  disk 1: %s -> %s\n", from, to);
  else
    hanoi(n - 1, from, via, to);
    format-out("  disk %d: %s -> %s\n", n, from, to);
    hanoi(n - 1, via, to, from);
  end if;
end function;
format-out("Towers of Hanoi (3 disks):\n");
hanoi(3, "A", "C", "B");

force-out();
