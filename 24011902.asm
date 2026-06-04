# BLM2022 Bilgisayar Organizasyonu - Odev 3
# Ogrenci: Omar Nuriyev - 24011902
#
# GOREV: 20 elemanli ARRAY dizisindeki her elemanin cift pozisyonlu bitlerindeki
#        (bit 0, 2, 4, ..., 30) 1-lerin sayisini COUNT dizisine kaydet.
#
# ALGORITMA:
#   Maske 0x55555555 (=0101...0101) AND ile cift bitleri sifirlamayan
#   tek bitleri sifirlar. Sonra 16 kez LSB'yi al, say, 2 bit saga kaydir.
#
# BELLEK DUZENI (dmem):
#   Adres 0x00-0x4C  : ARRAY[0..19]  (20 kelime)
#   Adres 0x50 (=80) : MASK = 0x55555555
#   Adres 0x54-0xA0  : COUNT[0..19] (20 kelime, yazilacak)
#
# KULLANILAN KOMUTLAR (Odev2 Soru1 / Q2 islemcisi):
#   addi, lw, and, andi, add, srai, beq, sw, jal
#
# YAZMAÇLAR:
#   a0 (x10) = ARRAY taban adresi = 0
#   a1 (x11) = COUNT taban adresi = 84 (0x54)
#   t6 (x31) = maske = 0x55555555
#   s0 (x8)  = dis dongu indeksi i (0..19)
#   t4 (x29) = sinir = 20
#   t1 (x6)  = bayt oteleme = i*4
#   t2 (x7)  = ARRAY[i] adresi
#   s2 (x18) = ARRAY[i] calisma kopyasi
#   s3 (x19) = cift bit 1 sayaci
#   s4 (x20) = ic dongu sayaci (16..0)
#   t0 (x5)  = bit alma gecici

_start:
    addi a0, x0, 0        # a0 = 0  (ARRAY taban)
    addi a1, x0, 84       # a1 = 84 (COUNT taban = 0x54)
    lw   t6, 80(x0)       # t6 = dmem[80] = 0x55555555 (maske)
    addi s0, x0, 0        # i = 0
    addi t4, x0, 20       # t4 = 20 (sinir)

outer_loop:               # PC = 0x14
    beq  s0, t4, done     # i == 20 ise cik (done'a atla, offset=+72)
    add  t1, s0, s0       # t1 = i * 2
    add  t1, t1, t1       # t1 = i * 4  (bayt oteleme)
    add  t2, a0, t1       # t2 = &ARRAY[i]
    lw   s2, 0(t2)        # s2 = ARRAY[i]
    and  s2, s2, t6       # s2 = ARRAY[i] & 0x55555555  (cift bitler)
    addi s3, x0, 0        # sayac = 0
    addi s4, x0, 16       # ic dongu sayaci = 16

inner_loop:               # PC = 0x34
    beq  s4, x0, next     # sayac == 0 ise ic donguden cik (offset=+24)
    andi t0, s2, 1        # t0 = s2 & 1  (en dusuk bit)
    add  s3, s3, t0       # sayac += t0
    srai s2, s2, 2        # s2 = s2 >> 2  (aritmetik, bit31=0 oldugundan mantiksal esit)
    addi s4, s4, -1       # ic dongu sayaci--
    jal  x0, inner_loop   # ic donguye don (offset=-20)

next:                     # PC = 0x4C
    add  t3, a1, t1       # t3 = &COUNT[i]  (t1 hala gecerli: i*4)
    sw   s3, 0(t3)        # COUNT[i] = sayac
    addi s0, s0, 1        # i++
    jal  x0, outer_loop   # dis donguye don (offset=-68)

done:                     # PC = 0x5C
    jal  x0, done         # sonsuz dongu (dur)

# --- MAKINE KODU (imem.mem icin hex) ---
# 00000513  addi a0, x0, 0
# 05400593  addi a1, x0, 84
# 05002F83  lw t6, 80(x0)
# 00000413  addi s0, x0, 0
# 01400E93  addi t4, x0, 20
# 05D40463  beq s0, t4, +72
# 00840333  add t1, s0, s0
# 00630333  add t1, t1, t1
# 006503B3  add t2, a0, t1
# 0003A903  lw s2, 0(t2)
# 01F97933  and s2, s2, t6
# 00000993  addi s3, x0, 0
# 01000A13  addi s4, x0, 16
# 000A0C63  beq s4, x0, +24
# 00197293  andi t0, s2, 1
# 005989B3  add s3, s3, t0
# 40295913  srai s2, s2, 2
# FFFA0A13  addi s4, s4, -1
# FEDFF06F  jal x0, -20
# 00658E33  add t3, a1, t1
# 013E2023  sw s3, 0(t3)
# 00140413  addi s0, s0, 1
# FBDFF06F  jal x0, -68
# 0000006F  jal x0, 0 (halt)
