#! /usr/bin/python3
test_dir = '../'
gdbMemfileDir = '../linux-testvectors/intermediate-outputs'
fixedMemfileDir = '../linux-testvectors'
infiles = ['bootmemGDB.txt', 'ramGDB.txt']
outfiles = ['bootmem.txt', 'ram.txt']
for i in range(len(infiles)):
    with open(f'{gdbMemfileDir}{infiles[i]}', 'r') as f:
        with open(f'{fixedMemfileDir}{outfiles[i]}', 'w') as w:
            for l in f:
                w.write(f'{"".join([x[2:] for x in l.split()[:0:-1]])}\n')
