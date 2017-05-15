# This file is a part of Julia. License is MIT: https://julialang.org/license

module GMP

export BigInt

import Base: *, +, -, /, <, <<, >>, >>>, <=, ==, >, >=, ^, (~), (&), (|), xor,
             binomial, cmp, convert, div, divrem, factorial, fld, gcd, gcdx, lcm, mod,
             ndigits, promote_rule, rem, show, isqrt, string, powermod,
             sum, trailing_zeros, trailing_ones, count_ones, base, tryparse_internal,
             bin, oct, dec, hex, isequal, invmod, prevpow2, nextpow2, ndigits0zpb,
             widen, signed, unsafe_trunc, trunc, iszero, big, flipsign, signbit

if Clong == Int32
    const ClongMax = Union{Int8, Int16, Int32}
    const CulongMax = Union{UInt8, UInt16, UInt32}
else
    const ClongMax = Union{Int8, Int16, Int32, Int64}
    const CulongMax = Union{UInt8, UInt16, UInt32, UInt64}
end
const CdoubleMax = Union{Float16, Float32, Float64}

gmp_version() = VersionNumber(unsafe_string(unsafe_load(cglobal((:__gmp_version, :libgmp), Ptr{Cchar}))))
gmp_bits_per_limb() = Int(unsafe_load(cglobal((:__gmp_bits_per_limb, :libgmp), Cint)))

const GMP_VERSION = gmp_version()
const GMP_BITS_PER_LIMB = gmp_bits_per_limb()

# GMP's mp_limb_t is by default a typedef of `unsigned long`, but can also be configured to be either
# `unsigned int` or `unsigned long long int`. The correct unsigned type is here named Limb, and must
# be used whenever mp_limb_t is in the signature of ccall'ed GMP functions.
if GMP_BITS_PER_LIMB == 32
    const Limb = UInt32
elseif GMP_BITS_PER_LIMB == 64
    const Limb = UInt64
else
    error("GMP: cannot determine the type mp_limb_t (__gmp_bits_per_limb == $GMP_BITS_PER_LIMB)")
end


mutable struct BigInt <: Integer
    alloc::Cint
    size::Cint
    d::Ptr{Limb}
    function BigInt()
        b = new(zero(Cint), zero(Cint), C_NULL)
        MPZ.init!(b)
        finalizer(b, cglobal((:__gmpz_clear, :libgmp)))
        return b
    end
end

function __init__()
    try
        if gmp_version().major != GMP_VERSION.major || gmp_bits_per_limb() != GMP_BITS_PER_LIMB
            error(string("The dynamically loaded GMP library (version $(gmp_version()) with __gmp_bits_per_limb == $(gmp_bits_per_limb()))\n",
                         "does not correspond to the compile time version (version $GMP_VERSION with __gmp_bits_per_limb == $GMP_BITS_PER_LIMB).\n",
                         "Please rebuild Julia."))
        end

        ccall((:__gmp_set_memory_functions, :libgmp), Void,
              (Ptr{Void},Ptr{Void},Ptr{Void}),
              cglobal(:jl_gc_counted_malloc),
              cglobal(:jl_gc_counted_realloc_with_old_size),
              cglobal(:jl_gc_counted_free))

        ZERO.alloc, ZERO.size, ZERO.d = 0, 0, C_NULL
        ONE.alloc, ONE.size, ONE.d = 1, 1, pointer(_ONE)
    catch ex
        Base.showerror_nostdio(ex,
            "WARNING: Error during initialization of module GMP")
    end
end


module MPZ
# wrapping of libgmp functions
# - "output parameters" are labeled x, y, z, and are returned when appropriate
# - constant input parameters are labeled a, b, c
# - a method modifying its input has a "!" appendend to its name, according to Julia's conventions
# - some convenient methods are added (in addition to the pure MPZ ones), e.g. `add(a, b) = add!(BigInt(), a, b)`
#   and `add!(x, a) = add!(x, x, a)`.
using Base.GMP: BigInt, Limb

const bitcnt_t = Culong

gmpz(op::Symbol) = (Symbol(:__gmpz_, op), :libgmp)

init!(x::BigInt) = (ccall((:__gmpz_init, :libgmp), Void, (Ptr{BigInt},), &x); x)
init() = init!(BigInt())
init2!(x::BigInt, a) = (ccall((:__gmpz_init2, :libgmp), Void, (Ptr{BigInt}, bitcnt_t), &x, a); x)
init2(a) = init2!(BigInt(), a)

sizeinbase(a::BigInt, b) = Int(ccall((:__gmpz_sizeinbase, :libgmp), Csize_t, (Ptr{BigInt}, Cint), &a, b))

for op in (:add, :sub, :mul, :fdiv_q, :tdiv_q, :fdiv_r, :tdiv_r, :gcd, :lcm, :and, :ior, :xor)
    op! = Symbol(op, :!)
    @eval begin
        $op!(x::BigInt, a::BigInt, b::BigInt) = (ccall($(gmpz(op)), Void, (Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}), &x, &a, &b); x)
        $op(a::BigInt, b::BigInt) = $op!(BigInt(), a, b)
        $op!(x::BigInt, a::BigInt) = $op!(x, x, a)
    end
end

invert!(x::BigInt, a::BigInt, b::BigInt) =
    ccall((:__gmpz_invert, :libgmp), Cint, (Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}), &x, &a, &b)
invert(a::BigInt, b::BigInt) = invert!(BigInt(), a, b)

for op in (:add_ui, :sub_ui, :mul_ui, :mul_2exp, :fdiv_q_2exp, :pow_ui, :bin_ui)
    op! = Symbol(op, :!)
    @eval begin
        $op!(x::BigInt, a::BigInt, b) = (ccall($(gmpz(op)), Void, (Ptr{BigInt}, Ptr{BigInt}, Culong), &x, &a, b); x)
        $op(a::BigInt, b) = $op!(BigInt(), a, b)
    end
end

ui_sub!(x::BigInt, a, b::BigInt) = (ccall((:__gmpz_ui_sub, :libgmp), Void, (Ptr{BigInt}, Culong, Ptr{BigInt}), &x, a, &b); x)
ui_sub(a, b::BigInt) = ui_sub!(BigInt(), a, b)

for op in (:scan1, :scan0)
    @eval $op(a::BigInt, b) = Int(ccall($(gmpz(op)), Culong, (Ptr{BigInt}, Culong), &a, b))
end

mul_si!(x::BigInt, a::BigInt, b) = (ccall((:__gmpz_mul_si, :libgmp), Void, (Ptr{BigInt}, Ptr{BigInt}, Clong), &x, &a, b); x)
mul_si(a::BigInt, b) = mul_si!(BigInt(), a, b)

for op in (:neg, :com, :sqrt, :set)
    op! = Symbol(op, :!)
    @eval begin
        $op!(x::BigInt, a::BigInt) = (ccall($(gmpz(op)), Void, (Ptr{BigInt}, Ptr{BigInt}), &x, &a); x)
        $op(a::BigInt) = $op!(BigInt(), a)
    end
end

for (op, T) in ((:fac_ui, Culong), (:set_ui, Culong), (:set_si, Clong), (:set_d, Cdouble))
    op! = Symbol(op, :!)
    @eval begin
        $op!(x::BigInt, a) = (ccall($(gmpz(op)), Void, (Ptr{BigInt}, $T), &x, a); x)
        $op(a) = $op!(BigInt(), a)
    end
end

popcount(a::BigInt) = ccall((:__gmpz_popcount, :libgmp), Culong, (Ptr{BigInt},), &a) % Int

mpn_popcount(d::Ptr{Limb}, s::Integer) = ccall((:__gmpn_popcount, :libgmp), Culong, (Ptr{Limb}, Csize_t), d, s) % Int
mpn_popcount(a::BigInt) = mpn_popcount(a.d, abs(a.size))

function tdiv_qr!(x::BigInt, y::BigInt, a::BigInt, b::BigInt)
    ccall((:__gmpz_tdiv_qr, :libgmp), Void, (Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}), &x, &y, &a, &b)
    x, y
end
tdiv_qr(a::BigInt, b::BigInt) = tdiv_qr!(BigInt(), BigInt(), a, b)

powm!(x::BigInt, a::BigInt, b::BigInt, c::BigInt) =
    (ccall((:__gmpz_powm, :libgmp), Void, (Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}), &x, &a, &b, &c); x)
powm(a::BigInt, b::BigInt, c::BigInt) = powm!(BigInt(), a, b, c)

function gcdext!(x::BigInt, y::BigInt, z::BigInt, a::BigInt, b::BigInt)
    ccall((:__gmpz_gcdext, :libgmp), Void, (Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}, Ptr{BigInt}),
          &x, &y, &z, &a, &b)
    x, y, z
end
gcdext(a::BigInt, b::BigInt) = gcdext!(BigInt(), BigInt(), BigInt(), a, b)

cmp(a::BigInt, b::BigInt) = ccall((:__gmpz_cmp, :libgmp), Cint, (Ptr{BigInt}, Ptr{BigInt}), &a, &b) % Int
cmp_si(a::BigInt, b) = ccall((:__gmpz_cmp_si, :libgmp), Cint, (Ptr{BigInt}, Clong), &a, b) % Int
cmp_ui(a::BigInt, b) = ccall((:__gmpz_cmp_ui, :libgmp), Cint, (Ptr{BigInt}, Culong), &a, b) % Int
cmp_d(a::BigInt, b) = ccall((:__gmpz_cmp_d, :libgmp), Cint, (Ptr{BigInt}, Cdouble), &a, b) % Int

get_str!(x, a, b::BigInt) = (ccall((:__gmpz_get_str,:libgmp), Ptr{Cchar}, (Ptr{Cchar}, Cint, Ptr{BigInt}), x, a, &b); x)
set_str!(x::BigInt, a, b) = ccall((:__gmpz_set_str, :libgmp), Cint, (Ptr{BigInt}, Ptr{UInt8}, Cint), &x, a, b) % Int
get_d(a::BigInt) = ccall((:__gmpz_get_d, :libgmp), Cdouble, (Ptr{BigInt},), &a)

limbs_write!(x::BigInt, a) = ccall((:__gmpz_limbs_write, :libgmp), Ptr{Limb}, (Ptr{BigInt}, Clong), &x, a)
limbs_finish!(x::BigInt, a) = ccall((:__gmpz_limbs_finish, :libgmp), Void, (Ptr{BigInt}, Clong), &x, a)
import!(x::BigInt, a, b, c, d, e, f) =
    ccall((:__gmpz_import, :libgmp), Void, (Ptr{BigInt}, Csize_t, Cint, Csize_t, Cint, Csize_t, Ptr{Void}),
          &x, a, b, c, d, e, f)

end # module MPZ

const ZERO = BigInt()
const ONE  = BigInt()
const _ONE = Limb[1]

widen(::Type{Int128})  = BigInt
widen(::Type{UInt128}) = BigInt
widen(::Type{BigInt})  = BigInt

signed(x::BigInt) = x

convert(::Type{BigInt}, x::BigInt) = x

function tryparse_internal(::Type{BigInt}, s::AbstractString, startpos::Int, endpos::Int, base_::Integer, raise::Bool)
    _n = Nullable{BigInt}()

    # don't make a copy in the common case where we are parsing a whole String
    bstr = startpos == start(s) && endpos == endof(s) ? String(s) : String(SubString(s,startpos,endpos))

    sgn, base, i = Base.parseint_preamble(true,Int(base_),bstr,start(bstr),endof(bstr))
    if !(2 <= base <= 62)
        raise && throw(ArgumentError("invalid base: base must be 2 ≤ base ≤ 62, got $base"))
        return _n
    end
    if i == 0
        raise && throw(ArgumentError("premature end of integer: $(repr(bstr))"))
        return _n
    end
    z = BigInt()
    if Base.containsnul(bstr)
        err = -1 # embedded NUL char (not handled correctly by GMP)
    else
        err = MPZ.set_str!(z, pointer(bstr)+(i-start(bstr)), base)
    end
    if err != 0
        raise && throw(ArgumentError("invalid BigInt: $(repr(bstr))"))
        return _n
    end
    Nullable(flipsign!(z, sgn))
end

convert(::Type{BigInt}, x::Union{Clong,Int32}) = MPZ.set_si(x)
convert(::Type{BigInt}, x::Union{Culong,UInt32}) = MPZ.set_ui(x)
convert(::Type{BigInt}, x::Bool) = BigInt(UInt(x))

unsafe_trunc(::Type{BigInt}, x::Union{Float32,Float64}) = MPZ.set_d(x)

function convert(::Type{BigInt}, x::Union{Float32,Float64})
    isinteger(x) || throw(InexactError())
    unsafe_trunc(BigInt,x)
end

function trunc(::Type{BigInt}, x::Union{Float32,Float64})
    isfinite(x) || throw(InexactError())
    unsafe_trunc(BigInt,x)
end

convert(::Type{BigInt}, x::Float16) = BigInt(Float64(x))
convert(::Type{BigInt}, x::Float32) = BigInt(Float64(x))

function convert(::Type{BigInt}, x::Integer)
    if x < 0
        if typemin(Clong) <= x
            return BigInt(convert(Clong,x))
        end
        b = BigInt(0)
        shift = 0
        while x < -1
            b += BigInt(~UInt32(x&0xffffffff))<<shift
            x >>= 32
            shift += 32
        end
        return -b-1
    else
        if x <= typemax(Culong)
            return BigInt(convert(Culong,x))
        end
        b = BigInt(0)
        shift = 0
        while x > 0
            b += BigInt(UInt32(x&0xffffffff))<<shift
            x >>>= 32
            shift += 32
        end
        return b
    end
end


rem(x::BigInt, ::Type{Bool}) = ((x&1)!=0)
function rem{T<:Union{Unsigned,Signed}}(x::BigInt, ::Type{T})
    u = zero(T)
    for l = 1:min(abs(x.size), cld(sizeof(T),sizeof(Limb)))
        u += (unsafe_load(x.d,l)%T) << ((sizeof(Limb)<<3)*(l-1))
    end
    flipsign(u, x)
end

rem(x::Integer, ::Type{BigInt}) = convert(BigInt, x)

function convert(::Type{T}, x::BigInt) where T<:Unsigned
    if sizeof(T) < sizeof(Limb)
        convert(T, convert(Limb,x))
    else
        0 <= x.size <= cld(sizeof(T),sizeof(Limb)) || throw(InexactError())
        x % T
    end
end

function convert(::Type{T}, x::BigInt) where T<:Signed
    n = abs(x.size)
    if sizeof(T) < sizeof(Limb)
        SLimb = typeof(Signed(one(Limb)))
        convert(T, convert(SLimb, x))
    else
        0 <= n <= cld(sizeof(T),sizeof(Limb)) || throw(InexactError())
        y = x % T
        ispos(x) ⊻ (y > 0) && throw(InexactError()) # catch overflow
        y
    end
end


(::Type{Float64})(n::BigInt, ::RoundingMode{:ToZero}) = MPZ.get_d(n)

function (::Type{T})(n::BigInt, ::RoundingMode{:ToZero}) where T<:Union{Float16,Float32}
    T(Float64(n,RoundToZero),RoundToZero)
end

function (::Type{T})(n::BigInt, ::RoundingMode{:Down}) where T<:CdoubleMax
    x = T(n,RoundToZero)
    x > n ? prevfloat(x) : x
end
function (::Type{T})(n::BigInt, ::RoundingMode{:Up}) where T<:CdoubleMax
    x = T(n,RoundToZero)
    x < n ? nextfloat(x) : x
end

function (::Type{T})(n::BigInt, ::RoundingMode{:Nearest}) where T<:CdoubleMax
    x = T(n,RoundToZero)
    if maxintfloat(T) <= abs(x) < T(Inf)
        r = n-BigInt(x)
        h = eps(x)/2
        if iseven(reinterpret(Unsigned,x)) # check if last bit is odd/even
            if r < -h
                return prevfloat(x)
            elseif r > h
                return nextfloat(x)
            end
        else
            if r <= -h
                return prevfloat(x)
            elseif r >= h
                return nextfloat(x)
            end
        end
    end
    x
end

convert(::Type{Float64}, n::BigInt) = Float64(n,RoundNearest)
convert(::Type{Float32}, n::BigInt) = Float32(n,RoundNearest)
convert(::Type{Float16}, n::BigInt) = Float16(n,RoundNearest)

promote_rule(::Type{BigInt}, ::Type{<:Integer}) = BigInt

big(::Type{<:Integer})  = BigInt
big(::Type{<:Rational}) = Rational{BigInt}

# Binary ops
for (fJ, fC) in ((:+, :add), (:-,:sub), (:*, :mul),
                 (:fld, :fdiv_q), (:div, :tdiv_q), (:mod, :fdiv_r), (:rem, :tdiv_r),
                 (:gcd, :gcd), (:lcm, :lcm),
                 (:&, :and), (:|, :ior), (:xor, :xor))
    @eval begin
        ($fJ)(x::BigInt, y::BigInt) = MPZ.$fC(x, y)
    end
end

/(x::BigInt, y::BigInt) = float(x)/float(y)

function invmod(x::BigInt, y::BigInt)
    z = zero(BigInt)
    ya = abs(y)
    if ya == 1
        return z
    end
    if (y==0 || MPZ.invert!(z, x, ya) == 0)
        throw(DomainError())
    end
    # GMP always returns a positive inverse; we instead want to
    # normalize such that div(z, y) == 0, i.e. we want a negative z
    # when y is negative.
    if y < 0
        MPZ.add!(z, y)
    end
    # The postcondition is: mod(z * x, y) == mod(big(1), m) && div(z, y) == 0
    return z
end

# More efficient commutative operations
for (fJ, fC) in ((:+, :add), (:*, :mul), (:&, :and), (:|, :ior), (:xor, :xor))
    fC! = Symbol(fC, :!)
    @eval begin
        ($fJ)(a::BigInt, b::BigInt, c::BigInt) = MPZ.$fC!(MPZ.$fC(a, b), c)
        ($fJ)(a::BigInt, b::BigInt, c::BigInt, d::BigInt) = MPZ.$fC!(MPZ.$fC!(MPZ.$fC(a, b), c), d)
        ($fJ)(a::BigInt, b::BigInt, c::BigInt, d::BigInt, e::BigInt) =
            MPZ.$fC!(MPZ.$fC!(MPZ.$fC!(MPZ.$fC(a, b), c), d), e)
    end
end

# Basic arithmetic without promotion
+(x::BigInt, c::CulongMax) = MPZ.add_ui(x, c)
+(c::CulongMax, x::BigInt) = x + c

-(x::BigInt, c::CulongMax) = MPZ.sub_ui(x, c)
-(c::CulongMax, x::BigInt) = MPZ.ui_sub(c, x)

+(x::BigInt, c::ClongMax) = c < 0 ? -(x, -(c % Culong)) : x + convert(Culong, c)
+(c::ClongMax, x::BigInt) = c < 0 ? -(x, -(c % Culong)) : x + convert(Culong, c)
-(x::BigInt, c::ClongMax) = c < 0 ? +(x, -(c % Culong)) : -(x, convert(Culong, c))
-(c::ClongMax, x::BigInt) = c < 0 ? -(x + -(c % Culong)) : -(convert(Culong, c), x)

*(x::BigInt, c::CulongMax) = MPZ.mul_ui(x, c)
*(c::CulongMax, x::BigInt) = x * c
*(x::BigInt, c::ClongMax) = MPZ.mul_si(x, c)
*(c::ClongMax, x::BigInt) = x * c

/(x::BigInt, y::Union{ClongMax,CulongMax}) = float(x)/y
/(x::Union{ClongMax,CulongMax}, y::BigInt) = x/float(y)

# unary ops
(-)(x::BigInt) = MPZ.neg(x)
(~)(x::BigInt) = MPZ.com(x)

<<(x::BigInt, c::UInt) = c == 0 ? x : MPZ.mul_2exp(x, c)
>>(x::BigInt, c::UInt) = c == 0 ? x : MPZ.fdiv_q_2exp(x, c)
>>>(x::BigInt, c::UInt) = x >> c

trailing_zeros(x::BigInt) = MPZ.scan1(x, 0)
trailing_ones(x::BigInt) = MPZ.scan0(x, 0)

count_ones(x::BigInt) = MPZ.popcount(x)

"""
    count_ones_abs(x::BigInt)

Number of ones in the binary representation of abs(x).
"""
count_ones_abs(x::BigInt) = iszero(x) ? 0 : MPZ.mpn_popcount(x)

divrem(x::BigInt, y::BigInt) = MPZ.tdiv_qr(x, y)

cmp(x::BigInt, y::BigInt) = MPZ.cmp(x, y)
cmp(x::BigInt, y::ClongMax) = MPZ.cmp_si(x, y)
cmp(x::BigInt, y::CulongMax) = MPZ.cmp_ui(x, y)
cmp(x::BigInt, y::Integer) = cmp(x, big(y))
cmp(x::Integer, y::BigInt) = -cmp(y, x)

cmp(x::BigInt, y::CdoubleMax) = isnan(y) ? throw(DomainError()) : MPZ.cmp_d(x, y)
cmp(x::CdoubleMax, y::BigInt) = -cmp(y, x)

isqrt(x::BigInt) = MPZ.sqrt(x)

^(x::BigInt, y::Culong) = MPZ.pow_ui(x, y)

function bigint_pow(x::BigInt, y::Integer)
    if y<0; throw(DomainError()); end
    if x== 1; return x; end
    if x==-1; return isodd(y) ? x : -x; end
    if y>typemax(Culong)
       x==0 && return x

       #At this point, x is not 1, 0 or -1 and it is not possible to use
       #gmpz_pow_ui to compute the answer. Note that the magnitude of the
       #answer is:
       #- at least 2^(2^32-1) ≈ 10^(1.3e9) (if Culong === UInt32).
       #- at least 2^(2^64-1) ≈ 10^(5.5e18) (if Culong === UInt64).
       #
       #Assume that the answer will definitely overflow.

       throw(OverflowError())
    end
    return x^convert(Culong, y)
end

^(x::BigInt , y::BigInt ) = bigint_pow(x, y)
^(x::BigInt , y::Bool   ) = y ? x : one(x)
^(x::BigInt , y::Integer) = bigint_pow(x, y)
^(x::Integer, y::BigInt ) = bigint_pow(BigInt(x), y)
^(x::Bool   , y::BigInt ) = Base.power_by_squaring(x, y)

function powermod(x::BigInt, p::BigInt, m::BigInt)
    r = MPZ.powm(x, p, m)
    return m < 0 && r > 0 ? MPZ.add!(r, m) : r # choose sign conistent with mod(x^p, m)
end

powermod(x::Integer, p::Integer, m::BigInt) = powermod(big(x), big(p), m)

function gcdx(a::BigInt, b::BigInt)
    if iszero(b) # shortcut this to ensure consistent results with gcdx(a,b)
        return a < 0 ? (-a,-ONE,b) : (a,one(BigInt),b)
        # we don't return the globals ONE and ZERO in case the user wants to
        # mutate the result
    end
    g, s, t = MPZ.gcdext(a, b)
    if t == 0
        # work around a difference in some versions of GMP
        if a == b
            return g, t, s
        elseif abs(a)==abs(b)
            return g, t, -s
        end
    end
    g, s, t
end

sum(arr::AbstractArray{BigInt}) = foldl(MPZ.add!, BigInt(0), arr)

factorial(x::BigInt) = isneg(x) ? BigInt(0) : MPZ.fac_ui(x)

binomial(n::BigInt, k::UInt) = MPZ.bin_ui(n, k)
binomial(n::BigInt, k::Integer) = k < 0 ? BigInt(0) : binomial(n, UInt(k))

==(x::BigInt, y::BigInt) = cmp(x,y) == 0
==(x::BigInt, i::Integer) = cmp(x,i) == 0
==(i::Integer, x::BigInt) = cmp(x,i) == 0
==(x::BigInt, f::CdoubleMax) = isnan(f) ? false : cmp(x,f) == 0
==(f::CdoubleMax, x::BigInt) = isnan(f) ? false : cmp(x,f) == 0
iszero(x::BigInt) = x.size == 0

<=(x::BigInt, y::BigInt) = cmp(x,y) <= 0
<=(x::BigInt, i::Integer) = cmp(x,i) <= 0
<=(i::Integer, x::BigInt) = cmp(x,i) >= 0
<=(x::BigInt, f::CdoubleMax) = isnan(f) ? false : cmp(x,f) <= 0
<=(f::CdoubleMax, x::BigInt) = isnan(f) ? false : cmp(x,f) >= 0

<(x::BigInt, y::BigInt) = cmp(x,y) < 0
<(x::BigInt, i::Integer) = cmp(x,i) < 0
<(i::Integer, x::BigInt) = cmp(x,i) > 0
<(x::BigInt, f::CdoubleMax) = isnan(f) ? false : cmp(x,f) < 0
<(f::CdoubleMax, x::BigInt) = isnan(f) ? false : cmp(x,f) > 0
isneg(x::BigInt) = x.size < 0
ispos(x::BigInt) = x.size > 0

signbit(x::BigInt) = isneg(x)
flipsign!(x::BigInt, y::Integer) = (signbit(y) && (x.size = -x.size); x)
flipsign( x::BigInt, y::Integer) = signbit(y) ? -x : x

string(x::BigInt) = dec(x)
show(io::IO, x::BigInt) = print(io, string(x))

bin(n::BigInt) = base( 2, n)
oct(n::BigInt) = base( 8, n)
dec(n::BigInt) = base(10, n)
hex(n::BigInt) = base(16, n)

bin(n::BigInt, pad::Int) = base( 2, n, pad)
oct(n::BigInt, pad::Int) = base( 8, n, pad)
dec(n::BigInt, pad::Int) = base(10, n, pad)
hex(n::BigInt, pad::Int) = base(16, n, pad)

function base(b::Integer, n::BigInt)
    2 <= b <= 62 || throw(ArgumentError("base must be 2 ≤ base ≤ 62, got $b"))
    nd = ndigits(n, b)
    str = Base._string_n(n < 0 ? nd+1 : nd)
    MPZ.get_str!(str, b, n)
end

function base(b::Integer, n::BigInt, pad::Integer)
    s = base(b, n)
    buf = IOBuffer()
    if n < 0
        s = s[2:end]
        write(buf, '-')
    end
    for i in 1:pad-sizeof(s) # `s` is known to be ASCII, and `length` is slower
        write(buf, '0')
    end
    write(buf, s)
    String(buf)
end

function ndigits0zpb(x::BigInt, b::Integer)
    b < 2 && throw(DomainError())
    x.size == 0 && return 0 # for consistency with other ndigits0z methods
    if ispow2(b) && 2 <= b <= 62 # GMP assumes b is in this range
        MPZ.sizeinbase(x, b)
    else
        # non-base 2 mpz_sizeinbase might return an answer 1 too big
        # use property that log(b, x) < ndigits(x, b) <= log(b, x) + 1
        n = MPZ.sizeinbase(x, 2)
        lb = log2(b) # assumed accurate to <1ulp (true for openlibm)
        q,r = divrem(n,lb)
        iq = Int(q)
        maxerr = q*eps(lb) # maximum error in remainder
        if r-1.0 < maxerr
            abs(x) >= big(b)^iq ? iq+1 : iq
        elseif lb-r < maxerr
            abs(x) >= big(b)^(iq+1) ? iq+2 : iq+1
        else
            iq+1
        end
    end
end

# below, ONE is always left-shifted by at least one digit, so a new BigInt is
# allocated, which can be safely mutated
prevpow2(x::BigInt) = -2 <= x <= 2 ? x : flipsign!(ONE << (ndigits(x, 2) - 1), x)
nextpow2(x::BigInt) = count_ones_abs(x) <= 1 ? x : flipsign!(ONE << ndigits(x, 2), x)

Base.checked_abs(x::BigInt) = abs(x)
Base.checked_neg(x::BigInt) = -x
Base.checked_add(a::BigInt, b::BigInt) = a + b
Base.checked_sub(a::BigInt, b::BigInt) = a - b
Base.checked_mul(a::BigInt, b::BigInt) = a * b
Base.checked_div(a::BigInt, b::BigInt) = div(a, b)
Base.checked_rem(a::BigInt, b::BigInt) = rem(a, b)
Base.checked_fld(a::BigInt, b::BigInt) = fld(a, b)
Base.checked_mod(a::BigInt, b::BigInt) = mod(a, b)
Base.checked_cld(a::BigInt, b::BigInt) = cld(a, b)
Base.add_with_overflow(a::BigInt, b::BigInt) = a + b, false
Base.sub_with_overflow(a::BigInt, b::BigInt) = a - b, false
Base.mul_with_overflow(a::BigInt, b::BigInt) = a * b, false

function Base.deepcopy_internal(x::BigInt, stackdict::ObjectIdDict)
    if haskey(stackdict, x)
        return stackdict[x]
    end
    y = MPZ.set(x)
    stackdict[x] = y
    return y
end

end # module
