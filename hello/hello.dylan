Module: hello

// Three upstream Open Dylan examples — verbatim — compiled to wasm64 and
// executed by the Dylan runtime in your browser:
//   1. quicksort        — opendylan/sources/examples/console/quicksort/
//   2. towers-of-hanoi  — opendylan/sources/examples/console/towers-of-hanoi/
//   3. factorial-big    — opendylan/sources/examples/console/factorial/

format-out("===== Open Dylan examples — running in your browser =====\n\n");


// =====================================================================
// quicksort  (sources: examples/console/quicksort)
// =====================================================================

define method sequence-quicksort
    (v :: <sequence>) => (sorted-v :: <sequence>)
  local method exchange (m, n) => ()
	  let t = v[m]; v[m] := v[n]; v[n] := t
	end method exchange,
        method partition (lo, hi, x) => (i, j)
	  let i = for (i from lo to hi, while: v[i] < x) finally i end;
	  let j = for (j from hi to lo by -1, while: x < v[j]) finally j end;
	  if (i <= j)
	    exchange(i, j);
	    partition(i + 1, j - 1, x)
	  else
	    values(i, j)
	  end
	end method partition,
        method sort (lo, hi) => ()
	  if (lo < hi)
	    let (i, j) = partition(lo, hi, v[round/(lo + hi, 2)]);
	    sort(lo, j);
	    sort(i, hi)
	  end
	end method sort;
  sort(0, v.size - 1);
  v
end method sequence-quicksort;

define constant <integer-vector> = limited(<vector>, of: <integer>);

define method integer-vector-quicksort
    (v :: <integer-vector>) => (sorted-v :: <integer-vector>)
  local method exchange (m :: <integer>, n :: <integer>) => ()
	  let t = v[m]; v[m] := v[n]; v[n] := t
	end method exchange,
        method partition
	    (lo :: <integer>, hi :: <integer>, x :: <integer>)
	 => (i :: <integer>, j :: <integer>)
	  let i :: <integer>
	    = for (i :: <integer> from lo to hi, while: v[i] < x) finally i end;
	  let j :: <integer>
	    = for (j :: <integer> from hi to lo by -1, while: x < v[j]) finally j end;
	  if (i <= j)
	    exchange(i, j);
	    partition(i + 1, j - 1, x)
	  else
	    values(i, j)
	  end
	end method partition,
        method sort (lo :: <integer>, hi :: <integer>) => ()
	  when (lo < hi)
	    let (i, j) = partition(lo, hi, v[round/(lo + hi, 2)]);
	    sort(lo, j);
	    sort(i, hi)
	  end;
	end method sort;
  sort(0, v.size - 1);
  v
end method integer-vector-quicksort;

define method display-sequence (s :: <sequence>)
  format-out("#[");
  let length :: <integer> = size(s);
  for (elem in s, i from 1)
    format-out("%s%s", elem, if (i < length) ", " else "" end);
  end for;
  format-out("]");
end;
define method display-sequence (s :: <string>) format-out("%=", s); end;

define method quicksort-demo () => ()
  format-out("---- quicksort ----\n");
  let data = vector("My dog has fleas.",
                    vector("My", "dog", "has", "fleas"),
                    vector('m', 'd', 'h', 'f'),
                    vector(2, 4, 1, 3));
  map(method (v)
        display-sequence(v);
        format-out(" sorted is ");
        display-sequence(sequence-quicksort(v));
        format-out("\n");
      end,
      data);

  let n :: <integer> = 50000;
  let orig :: <integer-vector> = make(<integer-vector>, size: n, fill: 0);
  let data :: <integer-vector> = make(<integer-vector>, size: n, fill: 0);
  // Stay within tagged-int range — with generic-arithmetic loaded
  // $maximum-integer is a <double-integer> that `random` doesn't handle.
  for (i :: <integer> from 0 below n) orig[i] := random(1000000000); end;
  // Only sequence-quicksort. Open Dylan loop-converts that one's
  // partition (its tail-recursive `partition(i + 1, j - 1, x)` becomes
  // a `br label %0` back to entry — verified in the emitted IR). The
  // typed `integer-vector-quicksort`'s partition does NOT get that
  // loop conversion — its recursive call goes via the method object
  // (`call %iep(@KpartitionF79, ...)`) and is followed by multi-value
  // extractvalue, so it isn't in LLVM's "tail position" and isn't
  // rewritten. On wasm without a `musttail` + `+tail-call` codegen
  // path, ~2500 frames overflow the JS engine's call stack. Fix would
  // be in the Open Dylan back-end (extend loop-conversion to typed
  // methods, or emit musttail on the recursive call).
  for (function in vector(sequence-quicksort),
       typename in #["<sequence>"])
    map-into(data, identity, orig);
    format-out("Sorting %d <integer>s as %s...", n, typename);
    let (seconds, microseconds) = timing () function(data); end;
    format-out(" took %d.%s seconds\n",
               seconds, integer-to-string(microseconds, size: 6));
  end;
  format-out("\n");
end method quicksort-demo;


// =====================================================================
// towers-of-hanoi  (sources: examples/console/towers-of-hanoi)
// =====================================================================

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
  for (disk in initial-disks) push(tower.disks, disk) end
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
    format-out("  %s: ", tower.name); print-tower(tower); format-out("\n")
  end;
  format-out("\n")
end method print-towers;

define method play-hanoi (height :: <integer>) => ()
  format-out("---- towers-of-hanoi (%d disks) ----\n", height);
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


// =====================================================================
// factorial-big  (sources: examples/console/factorial)
//   With generic-arithmetic + big-integers, $maximum-integer is 2^127 - 1
//   (the max of <double-integer>). factorial(25) fits; factorial(50) raises
//   <arithmetic-overflow-error>, caught by exception (e :: <error>).
// =====================================================================

define function factorial (n :: <integer>) => (n! :: <integer>)
  case
    n < 0     => error("Can't take factorial of negative integer: %d\n", n);
    n = 0     => 1;
    otherwise => n * factorial(n - 1);
  end
end;

define method factorial-demo () => ()
  format-out("---- factorial-big ----\n");
  format-out("$maximum-integer = %d\n", $maximum-integer);
  format-out("$minimum-integer = %d\n\n", $minimum-integer);
  for (n in #[0, 1, 5, 10, 20, 25, 50])
    block ()
      let n! = factorial(n);
      format-out("factorial(%d) = %d\n", n, n!);
    exception (e :: <error>)
      format-out("factorial(%d) - Error: %=\n", n, e);
    end block;
  end for;
  format-out("\n");
end method factorial-demo;


begin
  quicksort-demo();
  play-hanoi(5);
  factorial-demo();
end;
