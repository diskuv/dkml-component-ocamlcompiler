#!/bin/sh

# From https://ocaml.org/manual/coreexamples.html#s:standalone-programs
cat > gcd.ml <<EOF
  (* File gcd.ml *)
  let rec gcd a b =
    if b = 0 then a
    else gcd b (a mod b);;

  let main () =
    let a = int_of_string Sys.argv.(1) in
    let b = int_of_string Sys.argv.(2) in
    Printf.printf "%d\n" (gcd a b);
    exit 0;;
  main ();;
EOF

# Compile, run and verify on host ABI, for both bytecode and native code
_ci/tree/bin/ocamlc.opt   -verbose -o gcd.host.byte.exe gcd.ml
_ci/tree/bin/ocamlopt.opt -verbose -o gcd.host.exe      gcd.ml
file gcd.host.byte.exe
file gcd.host.exe      ; otool -h -f -v -L gcd.host.exe
./gcd.host.byte.exe 6 9
./gcd.host.exe      6 9
res=$(./gcd.host.byte.exe 6 9) ; [ "$res" -eq 3 ] || exit 107
res=$(./gcd.host.exe      6 9) ; [ "$res" -eq 3 ] || exit 107

# Compile, run and verify on the target ABI, except don't run or test the native code
printf "%s\n" "$TARGETABIS" | sed 's/;/\n/g' | sed 's/^\s*//; s/\s*$//' > _ci/tabi
while IFS= read -r _abientry
do
  _targetabi=$(printf "%s" "$_abientry" | sed 's/=.*//')

  echo "----------------------"
  echo "Compiling, running and verifying the target ABI $_targetabi"
  echo

  echo "ocamlc.opt ..."
  "_ci/tree/opt/mlcross/$_targetabi/bin/ocamlc.opt"   -verbose -o "gcd.$_targetabi.byte.exe" gcd.ml
  echo "ocamlopt.opt ..."
  "_ci/tree/opt/mlcross/$_targetabi/bin/ocamlopt.opt" -verbose -o "gcd.$_targetabi.exe"      gcd.ml

  echo
  echo "summary ..."
  file "gcd.$_targetabi.byte.exe"
  file "gcd.$_targetabi.exe"      ; otool -h -f -v -L "gcd.$_targetabi.exe"

  echo
  echo "bytecode testing ..."
  "./gcd.$_targetabi.byte.exe" 6 9
  res=$("./gcd.$_targetabi.byte.exe" 6 9) ; [ "$res" -eq 3 ] || exit 107

  echo
  echo "----------------------"
done < _ci/tabi
