Module: dylan-user

define library hello
  use common-dylan;
  use io;
  use generic-arithmetic;
  use big-integers;
end library;

define module hello
  use generic-arithmetic-common-dylan;
  use simple-format;
  use simple-random;
  use simple-profiling;
end module;
