Module: hello

// Three upstream Open Dylan examples — verbatim — compiled to wasm64 and
// executed by the Dylan runtime in your browser:
//   1. quicksort        — opendylan/sources/examples/console/quicksort/
//   2. towers-of-hanoi  — opendylan/sources/examples/console/towers-of-hanoi/
//   3. factorial-big    — opendylan/sources/examples/console/factorial/
// plus three demos written for this port, exercising float printing, the
// host-libm transcendentals bridge, and generic-function dispatch:
//   4. mandelbrot       — ASCII escape-time fractal, <double-float> arithmetic
//   5. sin & cos wave   — transcendentals (sin/cos/sqrt, $double-pi) plot
//   6. shapes           — class hierarchy + generic dispatch + closure sort

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
        // partition is intentionally a `while` loop instead of the upstream
        // tail-recursive `partition(i + 1, j - 1, x)`. Open Dylan's
        // self-call-to-loop pass in entry-points.dylan only fires when the
        // call target is a `<&lambda>` AND the enclosing lambda IS that
        // lambda; the typed local method here gets promoted to a generic
        // function call and ends up in the `<&generic-function>` overload
        // of `maybe-upgrade-required-call`, which never loop-converts. On
        // wasm without a tail-call codegen path that overflows the engine's
        // call stack at ~2500 frames. With a manual while-loop the call
        // disappears, the typed inner loops + element-setter stay, and the
        // partition body becomes a single basic-block loop in the IR.
        method partition
	    (lo0 :: <integer>, hi0 :: <integer>, x :: <integer>)
	 => (i :: <integer>, j :: <integer>)
	  let lo :: <integer> = lo0;
	  let hi :: <integer> = hi0;
	  let result-i :: <integer> = 0;
	  let result-j :: <integer> = 0;
	  block (return)
	    while (#t)
	      let i :: <integer>
	        = for (i :: <integer> from lo to hi, while: v[i] < x) finally i end;
	      let j :: <integer>
	        = for (j :: <integer> from hi to lo by -1, while: x < v[j]) finally j end;
	      if (i <= j)
	        exchange(i, j);
	        lo := i + 1;
	        hi := j - 1;
	      else
	        result-i := i;
	        result-j := j;
	        return(#f);
	      end if;
	    end while;
	  end block;
	  values(result-i, result-j)
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
  // Both quicksorts run now that integer-vector-quicksort's partition
  // is an explicit while-loop rather than tail-recursion (see comment
  // there for the back-end TCO gap this works around).
  for (function in vector(sequence-quicksort, integer-vector-quicksort),
       typename in #["<sequence>", "<integer-vector>"])
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


// =====================================================================
// mandelbrot — escape-time fractal in ASCII, pure <double-float> arithmetic
// =====================================================================

define constant $mandel-max-iterations :: <integer> = 32;

define function mandel-escape-count
    (cr :: <double-float>, ci :: <double-float>) => (n :: <integer>)
  let zr :: <double-float> = 0.0d0;
  let zi :: <double-float> = 0.0d0;
  let n :: <integer> = 0;
  while (n < $mandel-max-iterations & zr * zr + zi * zi < 4.0d0)
    let t = zr * zr - zi * zi + cr;
    zi := 2.0d0 * zr * zi + ci;
    zr := t;
    n := n + 1;
  end;
  n
end function mandel-escape-count;

define method mandelbrot-demo () => ()
  format-out("---- mandelbrot (escape-time, <double-float>) ----\n");
  let gradient = " .:-=+*#%";
  for (row from 0 below 22)
    let ci = -1.15d0 + 2.3d0 * as(<double-float>, row) / 21.0d0;
    for (col from 0 below 68)
      let cr = -2.1d0 + 2.8d0 * as(<double-float>, col) / 67.0d0;
      let n = mandel-escape-count(cr, ci);
      format-out("%c",
                 if (n >= $mandel-max-iterations) '@'
                 else gradient[min(n, 8)] end);
    end for;
    format-out("\n");
  end for;
  format-out("\n");
end method mandelbrot-demo;


// =====================================================================
// sine & cosine — transcendentals bridged to the host's libm
// =====================================================================

define method wave-demo () => ()
  format-out("---- sin & cos (transcendentals via host libm) ----\n");
  format-out("pi = %=   e = %=\n", $double-pi, $double-e);
  format-out("sin(pi/6) = %=   cos(pi/3) = %=   sqrt(2) = %=\n\n",
             sin($double-pi / 6.0d0), cos($double-pi / 3.0d0), sqrt(2.0d0));
  for (i from 0 below 40)
    let x = as(<double-float>, i) * $double-pi / 10.0d0;
    let s-col = round(sin(x) * 18.0d0) + 19;
    let c-col = round(cos(x) * 18.0d0) + 19;
    for (col from 0 below 39)
      format-out("%c",
                 case
                   col == s-col => '*';       // sine
                   col == c-col => 'o';       // cosine
                   col == 19    => '|';       // axis
                   otherwise    => ' ';
                 end);
    end for;
    format-out("\n");
  end for;
  format-out("        (* = sin, o = cos, two full periods top to bottom)\n\n");
end method wave-demo;


// =====================================================================
// shapes — Dylan generic functions dispatching on class
// =====================================================================

define abstract class <shape> (<object>)
  constant slot shape-name :: <byte-string>, required-init-keyword: name:;
end class <shape>;

define class <circle> (<shape>)
  constant slot radius :: <double-float>, required-init-keyword: radius:;
end class <circle>;

define class <box> (<shape>)
  constant slot box-width  :: <double-float>, required-init-keyword: width:;
  constant slot box-height :: <double-float>, required-init-keyword: height:;
end class <box>;

define generic shape-area (s :: <shape>) => (area :: <double-float>);

define method shape-area (c :: <circle>) => (area :: <double-float>)
  $double-pi * c.radius * c.radius
end method;

define method shape-area (b :: <box>) => (area :: <double-float>)
  b.box-width * b.box-height
end method;

// simple-format has no width directives (%-6s), so pad names by hand
define function pad (s :: <byte-string>, n :: <integer>) => (p :: <byte-string>)
  if (s.size >= n) s
  else concatenate(s, make(<byte-string>, size: n - s.size, fill: ' ')) end
end function pad;

define generic describe (s :: <shape>) => ();

define method describe (c :: <circle>) => ()
  format-out("  circle %s r = %=", pad(c.shape-name, 6), c.radius);
end method;

define method describe (b :: <box>) => ()
  format-out("  box    %s %= x %=", pad(b.shape-name, 6), b.box-width, b.box-height);
end method;

define method shapes-demo () => ()
  format-out("---- shapes (generic-function dispatch) ----\n");
  let shapes
    = vector(make(<circle>, name: "coin",  radius: 0.012d0),
             make(<box>,    name: "door",  width: 0.9d0, height: 2.1d0),
             make(<circle>, name: "wheel", radius: 0.66d0),
             make(<box>,    name: "tile",  width: 0.3d0, height: 0.3d0));
  // sort by area, descending — `test:` takes a closure over shape-area
  let sorted = sort(shapes,
                    test: method (a :: <shape>, b :: <shape>)
                            shape-area(a) > shape-area(b)
                          end);
  for (s :: <shape> in sorted)
    describe(s);
    format-out("   area = %=\n", shape-area(s));
  end;
  format-out("\n");
end method shapes-demo;


begin
  quicksort-demo();
  play-hanoi(5);
  factorial-demo();
  mandelbrot-demo();
  wave-demo();
  shapes-demo();
end;
