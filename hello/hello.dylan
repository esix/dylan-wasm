Module: hello

format-out("Hello from Dylan — running in your browser via wasm64!\n");
format-out("Open Dylan compiled to wasm64. Runtime, GC, dispatch — live.\n\n");

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
