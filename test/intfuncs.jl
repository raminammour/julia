# This file is a part of Julia. License is MIT: https://julialang.org/license

# Int32 and Int64 take different code paths -- test both
for T in (Int32, Int64)
    @test gcd(T(3)) === T(3)
    @test gcd(T(3), T(5)) === T(1)
    @test gcd(T(3), T(15)) === T(3)
    @test gcd(T(0), T(15)) === T(15)
    @test gcd(T(3), T(-15)) === T(3)
    @test gcd(T(-3), T(-15)) === T(3)
    @test gcd(T(0), T(0)) === T(0)

    @test gcd(T(2), T(4), T(6)) === T(2)

    @test gcd(typemax(T), T(1)) === T(1)
    @test gcd(-typemax(T), T(1)) === T(1)
    @test gcd(typemin(T), T(1)) === T(1)
    @test_throws OverflowError gcd(typemin(T), typemin(T))

    @test lcm(T(0)) === T(0)
    @test lcm(T(2)) === T(2)
    @test lcm(T(2), T(3)) === T(6)
    @test lcm(T(4), T(6)) === T(12)
    @test lcm(T(3), T(0)) === T(0)
    @test lcm(T(0), T(0)) === T(0)
    @test lcm(T(4), T(-6)) === T(12)
    @test lcm(T(-4), T(-6)) === T(12)

    @test lcm(T(2), T(4), T(6)) === T(12)

    @test lcm(typemax(T), T(1)) === typemax(T)
    @test lcm(-typemax(T), T(1)) === typemax(T)
    @test_throws OverflowError lcm(typemin(T), T(1))
    @test_throws OverflowError lcm(typemin(T), typemin(T))
end

@test gcdx(5, 12) == (1, 5, -2)
@test gcdx(5, -12) == (1, 5, 2)
@test gcdx(-25, -4) == (1, -1, 6)

@test invmod(6, 31) === 26
@test invmod(-1, 3) === 2
@test invmod(1, -3) === -2
@test invmod(-1, -3) === -1
@test invmod(0x2, 0x3) === 0x2
@test invmod(2, 0x3) === 2
@test_throws DomainError invmod(0, 3)

@test powermod(2, 3, 5) == 3
@test powermod(2, 3, -5) == -2

@test powermod(2, 0, 5) == 1
@test powermod(2, 0, -5) == -4

@test powermod(2, -1, 5) == 3
@test powermod(2, -2, 5) == 4
@test powermod(2, -1, -5) == -2
@test powermod(2, -2, -5) == -1

@test nextpow2(3) == 4
@test nextpow(2, 3) == 4
@test nextpow(2, 4) == 4
@test nextpow(2, 7) == 8
@test_throws DomainError nextpow(0, 3)
@test_throws DomainError nextpow(3, 0)

@test prevpow2(3) == 2
@test prevpow(2, 4) == 4
@test prevpow(2, 5) == 4
@test_throws DomainError prevpow(0, 3)
@test_throws DomainError prevpow(0, 3)

# issue #8266
@test ndigits(-15, 10) == 2
@test ndigits(-15, -10) == 2
@test ndigits(-1, 10) == 1
@test ndigits(-1, -10) == 2
@test ndigits(2, 10) == 1
@test ndigits(2, -10) == 1
@test ndigits(10, 10) == 2
@test ndigits(10, -10) == 3
@test ndigits(17, 10) == 2
@test ndigits(17, -10) == 3
@test ndigits(unsigned(17), -10) == 3

@test ndigits(146, -3) == 5

let (n, b) = rand(Int, 2)
    -1 <= b <= 1 && (b = 2) # invalid bases
    @test ndigits(n) == ndigits(big(n)) == ndigits(n, 10)
    @test ndigits(n, b) == ndigits(big(n), b)
end

for b in -1:1
    @test_throws DomainError ndigits(rand(Int), b)
end
@test ndigits(Int8(5)) == ndigits(5)

# issue #19367
@test ndigits(Int128(2)^64, 256) == 9

# test unsigned bases
@test ndigits(9, 0x2) == 4
@test ndigits(0x9, 0x2) == 4

@test bin('3') == "110011"
@test bin('3',7) == "0110011"
@test bin(3) == "11"
@test bin(3, 2) == "11"
@test bin(3, 3) == "011"
@test bin(-3) == "-11"
@test bin(-3, 3) == "-011"

@test oct(9) == "11"
@test oct(-9) == "-11"

@test dec(121) == "121"

@test hex(12) == "c"
@test hex(-12, 3) == "-00c"
@test num2hex(1243) == (Int == Int32 ? "000004db" : "00000000000004db")

@test base(2, 5, 7) == "0000101"

@test bits(Int16(3)) == "0000000000000011"
@test bits('3') == "00000000000000000000000000110011"
@test bits(1035) == (Int == Int32 ? "00000000000000000000010000001011" :
    "0000000000000000000000000000000000000000000000000000010000001011")
@test bits(Int128(3)) == "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011"

@test digits(4, 2) == [0, 0, 1]
@test digits(5, 3) == [2, 1]

# digits with negative bases
@testset "digits/base with negative bases" begin
    @testset "digits(n::$T, b)" for T in (Int, UInt, BigInt, Int32)
        @test digits(T(8163), -10) == [3, 4, 2, 2, 1]
        if !(T<:Unsigned)
            @test digits(T(-8163), -10) == [7, 7, 9, 9]
        end
    end
    @test [base(b, n)
           for n = [-10^9, -10^5, -2^20, -2^10, -100, -83, -50, -34, -27, -16, -7, -3, -2, -1,
                    0, 1, 2, 3, 4, 7, 16, 27, 34, 50, 83, 100, 2^10, 2^20, 10^5, 10^9]
           for b = [-2, -3, -7, -10, -60]] ==
               ["11000101101001010100101000000000", "11211100201202120012",
                "144246601121", "1000000000", "2hANlK", "111000111010100000",
                "122011122112", "615462", "100000", "1XlK", "1100000000000000000000",
                "11000202101022", "25055043", "19169584", "59Hi", "110000000000",
                "12102002", "3005", "1036", "Iu", "11101100", "121112", "1515",
                "1900", "2K", "11111101", "120011", "1651", "97", "2b", "11010010",
                "2121", "1616", "50", "1A", "100010", "2202", "51", "46", "1Q",
                "100101", "1000", "41", "33", "1X", "110000", "1102", "35", "24",
                "1i", "1001", "1202", "10", "13", "1r", "1101", "10", "14", "17",
                "1v", "10", "11", "15", "18", "1w", "11", "12", "16", "19", "1x", "0",
                "0", "0", "0", "0", "1", "1", "1", "1", "1", "110", "2", "2", "2",
                "2", "111", "120", "3", "3", "3", "100", "121", "4", "4", "4",
                "11011", "111", "160", "7", "7", "10000", "211", "152", "196", "G",
                "1101111", "12000", "146", "187", "R", "1100110", "12111", "136",
                "174", "Y", "1110110", "11022", "101", "150", "o", "1010111", "10002",
                "236", "123", "1xN", "110100100", "10201", "202", "100", "1xe",
                "10000000000", "2211011", "14012", "19184", "1h4",
                "100000000000000000000", "2001112212121", "162132144", "1052636",
                "1uqiG", "1101001101111100000", "21002022201", "1103425", "1900000",
                "SEe", "1001100111011111101111000000000", "120220201100111010001",
                "44642116066", "19000000000", "1xIpcEe"]
end

@test leading_ones(UInt32(Int64(2) ^ 32 - 2)) == 31
@test leading_ones(1) == 0
@test leading_zeros(Int32(1)) == 31
@test leading_zeros(UInt32(Int64(2) ^ 32 - 2)) == 0

@test count_zeros(Int64(1)) == 63

@test factorial(3) == 6
@test factorial(Int8(3)) === 6
@test_throws DomainError factorial(-3)
@test_throws DomainError factorial(Int8(-3))

@test isqrt(4) == 2
@test isqrt(5) == 2
@test isqrt(Int8(4)) === Int8(2)
@test isqrt(Int8(5)) === Int8(2)
# issue #4884
@test isqrt(9223372030926249000) == 3037000498
@test isqrt(typemax(Int128)) == parse(Int128,"13043817825332782212")
@test isqrt(Int128(typemax(Int64))^2-1) == 9223372036854775806
@test isqrt(0) == 0
for i = 1:1000
    n = rand(UInt128)
    s = isqrt(n)
    @test s*s <= n
    @test (s+1)*(s+1) > n
    n = rand(UInt64)
    s = isqrt(n)
    @test s*s <= n
    @test (s+1)*(s+1) > n
end

# issue #9786
let ptr = Ptr{Void}(typemax(UInt))
    for T in (Int, Cssize_t)
        @test T(ptr) == -1
        @test ptr == Ptr{Void}(T(ptr))
        @test typeof(Ptr{Float64}(T(ptr))) == Ptr{Float64}
    end
end

# issue #15911
@inferred string(1)
