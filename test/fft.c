///////////////////////////////////////////////////////////////////////////////
//
// Copyright (c) 2026 Juhani Vehvilainen. All rights reserved.
// 
// PROPRIETARY AND CONFIDENTIAL.
// Unauthorized copying, modification, or distribution of this file, 
// via any medium, is strictly prohibited.
//
///////////////////////////////////////////////////////////////////////////////

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <assert.h>

// #define USE_FLOATS  1
#define USE_FP16   1

#ifndef LOG2LEN
#error Need to define LOG2LEN at compile time
#endif

#ifdef RADIX4
#define LOG4LEN (LOG2LEN/2)
#if 2*LOG4LEN != LOG2LEN
#error FFT length is not compatible with radix-4
#endif
#endif

#ifndef UNROLL
#define UNROLL 1
#endif

#if V == 2
#define LOG2V  1
#elif V == 4
#define LOG2V  2
#elif V == 8
#define LOG2V  3
#elif V == 16
#define LOG2V  4
#elif V == 32
#define LOG2V  5
#elif V == 64
#define LOG2V  6
#else
#error Vector length must be power of two between 2 and 64
#endif

#define FFT_LEN     (1<<LOG2LEN)
#define pi          ((float) M_PI)

#if USE_FLOATS
typedef struct complex {
  float real, imag;
} complex_t;

#define COMPLEX(r, i) (complex_t) { .real = r, .imag = i }
#define COMPLEX_FROM_FLOAT(r, i) COMPLEX(r, i)
#define COMPLEX_ADD(a, b) (complex_t) { (a).real + (b).real, (a).imag + (b).imag }
#define COMPLEX_SUB(a, b) (complex_t) { (a).real - (b).real, (a).imag - (b).imag }
#define COMPLEX_MUL(a, b) (complex_t) { (a).real*(b).real-(a).imag*(b).imag, (a).real*(b).imag+(a).imag*(b).real }
#define COMPLEX_ABS(a) sqrtf((a).real*(a).real + (a).imag*(a).imag)
#define TO_DOUBLE(a) ((double) (a))

#elif USE_FP16

// #define TEST_FP16        1
// #define DEBUG_FP16       1
#define INT_PREC    4

#define FP16_PRECISION   12  // Includes implicit '1'
#define FP16_MANT_BITS   (FP16_PRECISION - 1)
#define FP16_EXP_BITS    (8*sizeof(fp16_t) - 1 - FP16_MANT_BITS)
#define FP16_EXP_BIAS    (((1<<FP16_EXP_BITS)/2)-1)

#define MASK(n)          ((1<<(n)) - 1)
#define COMPLEX(r, i) (complex_t) { .real = r, .imag = i }
#define COMPLEX_FROM_FLOAT(r, i) (complex_t) { .real = fp16_from_float(r), .imag = fp16_from_float(i) }

#define MUL(a, b) fp16_mul_denorm(a, b)
#define ADD(a, b) fp16_add(a, b)
#define ADD_DN(a, b) fp16_add_denorm(a, b)
#define SUB(a, b) fp16_sub(a, b)
#define SUB_DN(a, b) fp16_sub_denorm(a, b)
#define NORM(a) fp16_norm(a)

#define COMPLEX_ADD(a, b) (complex_t) { ADD((a).real, (b).real), ADD((a).imag, (b).imag) }
#define COMPLEX_SUB(a, b) (complex_t) { SUB((a).real, (b).real), SUB((a).imag, (b).imag) }
#define COMPLEX_MUL(a, b) (complex_t) { NORM(SUB_DN(MUL((a).real, (b).real), MUL((a).imag, (b).imag))), \
      NORM(ADD_DN(MUL((a).real, (b).imag), MUL((a).imag, (b).real))) }

#define COMPLEX_ABS(a) 0 // sqrtf((a).real*(a).real + (a).imag*(a).imag)
#define TO_DOUBLE(a) ((double) fp16_to_float(a))

#define FP16_MANTISSA(a)   (((a) & MASK(FP16_EXP_BITS+FP16_MANT_BITS)) != 0 ? (((a) & MASK(FP16_MANT_BITS)) | (1<<FP16_MANT_BITS)) : 0)
#define FP16_EXP(a)        (((a)>>FP16_MANT_BITS) & MASK(FP16_EXP_BITS))
#define FP16_SIGN(a)       (((a)>>(FP16_MANT_BITS + FP16_EXP_BITS)) & 1)
#define FP16_PACK(s, e, m) ((((s) & 1)<<(FP16_MANT_BITS + FP16_EXP_BITS)) \
			    | (((e) & MASK(FP16_EXP_BITS))<<FP16_MANT_BITS) \
			    | ((m) & MASK(FP16_MANT_BITS)))
#define FP16_PACK_DENORM(s, e, m) ((((s) & 1)<<(FP16_MANT_BITS + FP16_EXP_BITS+16)) \
				   | (((e) & MASK(FP16_EXP_BITS))<<(FP16_MANT_BITS+16)) \
				   | ((m) & MASK(FP16_PRECISION+INT_PREC)))
#define DENORM_FROM_FP16(a) FP16_PACK_DENORM(FP16_SIGN(a), FP16_EXP(a), FP16_MANTISSA(a)<<INT_PREC)

typedef uint16_t fp16_t;

typedef uint32_t fp16_denorm_t;

typedef fp16_t part_t;

typedef struct complex {
  part_t real, imag;
} complex_t;

fp16_t fp16_from_float(float a)
{
  float f_mant = 0.0f;
  int f_exp, s = 0;
  
  f_mant = frexpf(a, &f_exp);

  s = f_mant < 0.0f ? 1 : 0;
  f_mant = fabsf(f_mant);

  // printf("a = %.3f: s=%d  mant=%.3f  exp=%d\n", a, s, f_mant, f_exp);
  
  f_exp += FP16_EXP_BIAS;
    
  if(f_mant == 0.0f || f_exp < 0)
    // Underflow to zero
    return 0;
  
  return FP16_PACK(s, f_exp, (int16_t) (f_mant * (1<<FP16_PRECISION)));
}

fp16_t fp16_from_int(int a)
{
  return fp16_from_float((float) a);
}

float fp16_to_float(fp16_t a)
{
  float result = 0.0f;

  if(a == 0)
    return 0.0f;
  
  result = (float) FP16_MANTISSA(a) / (float) (1<<FP16_PRECISION);

  if(FP16_SIGN(a))
    result = -result;
  
  return ldexpf(result, FP16_EXP(a) - FP16_EXP_BIAS);
}

fp16_denorm_t fp16_mul_denorm(fp16_t a, fp16_t b)
{
#if DEBUG_FP16
  printf("\nmul %.4f x %.4f\n", TO_DOUBLE(a), TO_DOUBLE(b));
  
  printf("mult mant = %.3f x mant = %.3f\n", (double) ((float) FP16_MANTISSA(a)/(1<<FP16_PRECISION)),
  	 (double) ((float) FP16_MANTISSA(b)/(1<<FP16_PRECISION)));
#endif
  
  int s = FP16_SIGN(a) ^ FP16_SIGN(b);
  int exp = FP16_EXP(a) + FP16_EXP(b) - FP16_EXP_BIAS;
  uint32_t mant = (FP16_MANTISSA(a) * FP16_MANTISSA(b)) >> (FP16_PRECISION - 1 - INT_PREC);

  if(mant > (1<<(FP16_PRECISION + INT_PREC))) {
    exp ++;
    mant >>= 1;
  }
  
  if(exp > (1<<FP16_EXP_BITS)) {
    // Overflow
    exp = (1<<FP16_EXP_BITS);
    mant = (1<<(FP16_PRECISION + INT_PREC))-1;
    
  }

  fp16_denorm_t result = 0;
  
  if(mant > 0 && exp > 1)
    // No underflow
    result = FP16_PACK_DENORM(s, exp - 1, mant);

#if DEBUG_FP16
  printf("  result mant = %.3f \n", (double) ((float) mant/(1<<(FP16_PRECISION+INT_PREC))));
  //  printf("  result = %.4f \n", TO_DOUBLE(result));
#endif
  
  return result;
}

fp16_t fp16_norm(fp16_denorm_t a)
{
  int s = FP16_SIGN(a>>16);
  int exp = FP16_EXP(a>>16);
  uint16_t mant = a & 0xFFFF;

  if((mant>>INT_PREC) == 0) {
    // Underflow to 0
    exp = 0;
    
  } else {
    // Normalize so mantissa is between 0.5 and 1
    
    while(mant < (1<<(FP16_PRECISION + INT_PREC))/2) {
      exp--;
      mant <<= 1;
    }
  }

  fp16_t result = 0;
  
  if(exp > 0) {
    // Not underflow
    
    if(exp > (1<<FP16_EXP_BITS)-1) {
      // Overflow
      exp = (1<<FP16_EXP_BITS)-1;
      mant = (1<<(FP16_PRECISION + INT_PREC))-1;
    }

    result = FP16_PACK(s, exp, mant>>INT_PREC);
  }

  return result;
}

fp16_t fp16_mul(fp16_t a, fp16_t b)
{
  return fp16_norm(fp16_mul_denorm(a, b));
}

fp16_denorm_t fp16_add_denorm(fp16_denorm_t a, fp16_denorm_t b)
{
  if(FP16_EXP(a>>16) < FP16_EXP(b>>16)) {
    // Swap so exp(a) is always >= exp(b)
    fp16_denorm_t t = a;
    a = b;
    b = t;
  }

#if DEBUG_FP16
  printf("add %.4f + %.4f\n", TO_DOUBLE(a), TO_DOUBLE(b));
  printf("add mant = %.3f + mant = %.3f\n", (double) ((float) FP16_MANTISSA(a)/(1<<FP16_PRECISION)),
   	 (double) ((float) FP16_MANTISSA(b)/(1<<FP16_PRECISION)));
#endif
  
  int exp_a = FP16_EXP(a>>16);
  int32_t mant_a = a & 0xFFFF;
  int32_t mant_b = (b & 0xFFFF)>>(exp_a - FP16_EXP(b>>16));

  if(FP16_SIGN(a>>16))
    mant_a = -mant_a;
  
  if(FP16_SIGN(b>>16))
    mant_b = -mant_b;

  mant_a += mant_b;

  int s = mant_a < 0 ? 1 : 0;

  if(s)
    mant_a = -mant_a;

  if(mant_a > (1<<(FP16_PRECISION+INT_PREC))-1) {
    // Mantissa grew beyond 1, shift right
    exp_a++;
    mant_a >>= 1;
    
  }

  return FP16_PACK_DENORM(s, exp_a, mant_a);
  /*
  else if((mant_a == 0) {
    // Underflow to 0
    exp_a = -1;
    
  } else {
    // Normalize so mantissa is between 0.5 and 1
    
    while(mant_a < (1<<FP16_PRECISION)/2) {
      exp_a--;
      mant_a <<= 1;
    }
  }

  fp16_t result = 0;
  
  if(exp_a >= 0) {
    // Not underflow
    
    if(exp_a > (1<<FP16_EXP_BITS)-1) {
      // Overflow
      exp_a = (1<<FP16_EXP_BITS)-1;
      mant_a = (1<<FP16_PRECISION)-1;
    }

    result = FP16_PACK(s, exp_a, mant_a);
  }
  
#if DEBUG_FP16
  printf("  result mant = %.3f \n", (double) ((float) mant_a/(1<<FP16_PRECISION)));
  printf("  result = %.4f \n", TO_DOUBLE(result));
#endif
  
  return result;
  */
}

fp16_t fp16_add(fp16_t a, fp16_t b)
{
  return fp16_norm(fp16_add_denorm(DENORM_FROM_FP16(a), DENORM_FROM_FP16(b)));
}

fp16_denorm_t fp16_neg_denorm(fp16_denorm_t a)
{
  return a ^ (1<<(16 + FP16_MANT_BITS + FP16_EXP_BITS));
}

fp16_t fp16_neg(fp16_t a)
{
  return a ^ (1<<(FP16_MANT_BITS + FP16_EXP_BITS));
}

fp16_t fp16_sub(fp16_t a, fp16_t b)
{
  return fp16_add(a, fp16_neg(b));
}

fp16_denorm_t fp16_sub_denorm(fp16_denorm_t a, fp16_denorm_t b)
{
  return fp16_add_denorm(a, fp16_neg_denorm(b));
}

#else

#ifndef PRECISION
#define PRECISION 12
#endif

typedef int16_t part_t;

typedef struct complex {
  part_t real, imag;
} complex_t;

const int integer_bits = 8*sizeof(part_t) - PRECISION;

#define COMPLEX(r, i) (complex_t) { .real = r, .imag = i }
#define COMPLEX_FROM_FLOAT(r, i) (complex_t) { .real = (part_t) ((r) * (float) (1<<PRECISION)), .imag = (part_t) ((i) * (float) (1<<PRECISION)) }

int32_t saturate(int32_t a, int p)
{
  int32_t min_value = -1L<<(p + integer_bits - 1), max_value = (1L<<(p + integer_bits - 1)) - 1;
  if(a < min_value)
    a = min_value;
  else if(a > max_value)
    a = max_value;
  return a;
}

#define MUL(a, b) ((int32_t) a * (int32_t)b)
#define NORM(a) (part_t) (saturate(a, 2*PRECISION)>>PRECISION)
#define ADD(a, b) saturate((int32_t) a + (int32_t) b, PRECISION)
#define SUB(a, b) saturate((int32_t) a - (int32_t) b, PRECISION)
#define COMPLEX_ADD(a, b) (complex_t) { ADD((a).real, (b).real), ADD((a).imag, (b).imag) }
#define COMPLEX_SUB(a, b) (complex_t) { SUB((a).real, (b).real), SUB((a).imag, (b).imag) }
#define COMPLEX_MUL(a, b) (complex_t) { NORM(MUL((a).real, (b).real)-MUL((a).imag, (b).imag)), \
      NORM(MUL((a).real, (b).imag)+MUL((a).imag, (b).real)) }
#define COMPLEX_ABS(a) 0 // sqrtf((a).real*(a).real + (a).imag*(a).imag)
#define TO_DOUBLE(a) ((a)/(double) (1<<PRECISION))
#endif

complex_t fft_data[FFT_LEN];
complex_t w[FFT_LEN];

uint32_t to_machine(complex_t *a)
{
#if USE_FLOATS
  int32_t result = (int32_t) (a->real * (float) (1<<PRECISION));
  result = result<<16;
  result |= ((int32_t) (a->imag * (float) (1<<PRECISION))) & 0xFFFF;
  return result;
#else
  return ((uint32_t) a->real)<<8*sizeof(part_t) | (uint16_t) a->imag;
#endif
}

int bit_reverse(int I)
{
  int j = 0, result = 0;
  for(j = 0; j < LOG2LEN; j++) {
    result = (result<<1) | (I & 1);
    I >>= 1;
  }
  return result;
}

int radix4_digit_reverse(int I)
{
  int j = 0, result = 0;
  for(j = 0; j < LOG2LEN/2; j++) {
    result = (result<<2) | (I & 3);
    I >>= 2;
  }
  return result;
}

void bit_reversal_permutation(complex_t *data)
{
  int i = 0;
  
  for(i = 0; i < FFT_LEN; i++) {
    int rev = bit_reverse(i);

    if(i < rev) {
      complex_t temp = data[i];
      data[i] = data[rev];
      data[rev] = temp;
    }
  }
}

void radix4_digit_reversal_permutation(complex_t *data)
{
  int i = 0;
  
  for(i = 0; i < FFT_LEN; i++) {
    int rev = radix4_digit_reverse(i);

    if(i < rev) {
      complex_t temp = data[i];
      data[i] = data[rev];
      data[rev] = temp;
    }
  }
}

complex_t complex_array_ref(complex_t array[], int index, int base)
{
  assert(index < FFT_LEN);
  
  complex_t value = array[index];
  printf("%.4x ~%.8x | ", base + index*4, to_machine(&value));
  return value;
} 

void complex_array_set(complex_t value, complex_t array[], int index, int base)
{
  assert(index < FFT_LEN);
  
  printf("%.4x:=%.8x | ", base + index*4, to_machine(&value));
  array[index] = value;
} 

void complex_vector_print(complex_t value[])
{
  int i = 0;
  for(i = 0; i < V; i++)
    printf("%.8x (%.3f +i%.3f), ", to_machine(&value[i]), TO_DOUBLE(value[i].real), TO_DOUBLE(value[i].imag));
  printf("\n");
}

void complex_vector_write(const complex_t value[], complex_t array[], int index, int stride, int base)
{
  int i = 0;
  for(i = 0; i < V; i++)
    complex_array_set(value[i], array, index + i*stride, base);
  printf("\n");
}

void complex_vector_read(complex_t value[], complex_t array[], int index, int stride, int base)
{
  int i = 0;
  for(i = 0; i < V; i++)
    value[i] = complex_array_ref(array, index + i*stride, base);
  printf("\n");
}

void complex_vector_read_mul(int num, complex_t value[], complex_t array[], int index, int stride, int base)
{
  int i = 0;
  for(i = 0; i < num; i++)
    complex_vector_read(&value[i*V], array, index + i*V*stride, stride, base);
}

void complex_vector_write_mul(int num, const complex_t value[], complex_t array[], int index, int stride, int base)
{
  int i = 0;
  for(i = 0; i < num; i++)
    complex_vector_write(&value[i*V], array, index + i*V*stride, stride, base);
}

void complex_vector_mul(complex_t result[], complex_t a[], complex_t b[])
{
  int i = 0;
  for(i = 0; i < V; i++)
    result[i] = COMPLEX_MUL(a[i], b[i]);
}

void complex_vector_mul_bc(complex_t result[], complex_t a[], complex_t *b)
{
  int i = 0;
  for(i = 0; i < V; i++)
    result[i] = COMPLEX_MUL(a[i], *b);
}

void complex_vector_add(complex_t result[], complex_t a[], complex_t b[])
{
  int i = 0;
  for(i = 0; i < V; i++)
    result[i] = COMPLEX_ADD(a[i], b[i]);
}

void complex_vector_sub(complex_t result[], complex_t a[], complex_t b[])
{
  int i = 0;
  for(i = 0; i < V; i++)
    result[i] = COMPLEX_SUB(a[i], b[i]);
}

void fft(complex_t A[])
{
  int s = 0, k = 0, m = 0, half_m = 0, j = 0, tab_step = 0;

  for(s = 1; s <= LOG2LEN; s++) {
    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);
    
    for(k = 0; k < FFT_LEN; k += m) {
      for(j = 0; j < half_m; j++) {
	complex_t omega = w[j * tab_step];
	complex_t t = COMPLEX_MUL(omega, A[k + j + half_m]);
	complex_t u = A[k + j];

	A[k + j] = COMPLEX_ADD(u, t);
	A[k + j + half_m] = COMPLEX_SUB(u, t);
      }
    }
  }
}

void fft_with_vectors(complex_t A[])
{
  int s = 0, m = 0, half_m = 0, tab_step = 0;

  for(s = 1; s <= LOG2V; s++) {
    //
    // Early stage: our vectors will handle k with striding by m
    //
    // if(half_m < V)
    //   m/2 < V <==> m < 2*V <==> 1<<s < 2*V <==> s < LOG2V + 1

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);

    int j = 0;
      
    for(j = 0; j < half_m; j++) {
      int v = 0;
      complex_t omega = complex_array_ref(w, j * tab_step, 0x4000); printf("\n");

      for(v = 0; v < FFT_LEN; v += V*m) {
	printf("---\ns = %d j = %d v = %d\n---\n", s, j, v);
      
	complex_t a[V], t[V], u[V], x[V], y[V];

	complex_vector_read(u, A, j + v, m, 0x130);
	complex_vector_read(a, A, j + v + half_m, m, 0x130);
	complex_vector_mul_bc(t, a, &omega);
	complex_vector_add(x, u, t);
	complex_vector_sub(y, u, t);
	complex_vector_write(x, A, j + v, m, 0x130);
	complex_vector_write(y, A, j + v + half_m, m, 0x130);
      }
    }
  }
  
  for(s = LOG2V+1; s <= LOG2LEN; s++) {
    //
    // Late stage: our vectors will handle j directly, striding used only for w
    //

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);
    
    int k = 0;
    
    for(k = 0; k < FFT_LEN; k += m) {
      int v = 0;
	
      for(v = 0; v < half_m; v += V) {
	printf("---\ns = %d k = %d v = %d\n---\n", s, k, v);
      
	complex_t omega[V], a[V], t[V], u[V], x[V];
	  
	complex_vector_read(omega, w, v * tab_step, tab_step, 0x4000);
	complex_vector_read(u, A, k + v, 1, 0x130);
	complex_vector_read(a, A, k + v + half_m, 1, 0x130);
	complex_vector_mul(t, a, omega);
	complex_vector_add(x, u, t);
	complex_vector_write(x, A, k + v, 1, 0x130);
	complex_vector_sub(x, u, t);
	complex_vector_write(x, A, k + v + half_m, 1, 0x130);
      }
    }
  }
}

#define EFF2_LOG2V  (LOG2V+1)
#define EFF2_V      (1<<EFF2_LOG2V)
  
void fft_vectors_unroll2(complex_t A[])
{
  int s = 0, m = 0, half_m = 0, tab_step = 0;
  int count = 0;

  for(s = 1; s <= EFF2_LOG2V; s++) {
    //
    // Early stage: our vectors will handle k with striding by m
    //
    // if(half_m < V)
    //   m/2 < V <==> m < 2*V <==> 1<<s < 2*V <==> s < LOG2V + 1

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);

    int j = 0;
      
    for(j = 0; j < half_m; j++) {
      int v = 0;
      complex_t omega = complex_array_ref(w, j * tab_step, 0x4000); printf("\n");

      for(v = 0; v < FFT_LEN; v += EFF2_V*m) {
	printf("---\ns = %d j = %d v = %d\n---\n", s, j, v);
	
	complex_t a[EFF2_V], t[EFF2_V], u[EFF2_V], x[EFF2_V], y[EFF2_V];

	complex_vector_read_mul(2, u, A, j + v, m, 0x130);
	complex_vector_read_mul(2, a, A, j + v + half_m, m, 0x130);
	
	complex_vector_mul_bc(t, a, &omega);
	complex_vector_mul_bc(&t[V], &a[V], &omega);
	
	complex_vector_add(x, u, t);
	complex_vector_add(&x[V], &u[V], &t[V]);
	complex_vector_sub(y, u, t);
	complex_vector_sub(&y[V], &u[V], &t[V]);
	
	complex_vector_write_mul(2, x, A, j + v, m, 0x130);
	complex_vector_write_mul(2, y, A, j + v + half_m, m, 0x130);
      }
    }
  }

  count = 0;
  
  for(s = EFF2_LOG2V+1; s <= LOG2LEN; s++) {
    //
    // Late stage: our vectors will handle j directly, striding used only for w
    //

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);
    
    int k = 0;
    
    for(k = 0; k < FFT_LEN; k += m) {
      int v = 0;
	
      for(v = 0; v < half_m; v += EFF2_V) {
	printf("---\ns = %d k = %d v = %d\n---\n", s, k, v);
	
	complex_t omega[EFF2_V], a[EFF2_V], t[EFF2_V], u[EFF2_V], x[EFF2_V];
	  
	complex_vector_read_mul(2, omega, w, v * tab_step, tab_step, 0x4000);
	complex_vector_read_mul(2, u, A, k + v, 1, 0x130);
	complex_vector_read_mul(2, a, A, k + v + half_m, 1, 0x130);
	complex_vector_mul(t, a, omega);
	complex_vector_mul(&t[V], &a[V], &omega[V]);
	complex_vector_add(x, u, t);
	complex_vector_add(&x[V], &u[V], &t[V]);
	complex_vector_write_mul(2, x, A, k + v, 1, 0x130);
	complex_vector_sub(x, u, t);
	complex_vector_sub(&x[V], &u[V], &t[V]);
	complex_vector_write_mul(2, x, A, k + v + half_m, 1, 0x130);
      }
    }
  }
}

#define EFF4_LOG2V  (LOG2V+2)
#define EFF4_V      (1<<EFF4_LOG2V)
  
void fft_vectors_unroll4(complex_t A[])
{
  int s = 0, m = 0, half_m = 0, tab_step = 0;
  int count = 0;

  for(s = 1; s <= EFF4_LOG2V; s++) {
    //
    // Early stage: our vectors will handle k with striding by m
    //
    // if(half_m < V)
    //   m/2 < V <==> m < 2*V <==> 1<<s < 2*V <==> s < LOG2V + 1

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);

    int j = 0;
      
    for(j = 0; j < half_m; j++) {
      int v = 0;
      complex_t omega = complex_array_ref(w, j * tab_step, 0x4000); printf("\n");

      for(v = 0; v < FFT_LEN; v += EFF4_V*m) {
	printf("---\ns = %d j = %d v = %d\n---\n", s, j, v);
	
	complex_t a[EFF4_V], t[EFF4_V], u[EFF4_V], x[EFF4_V], y[EFF4_V];

	complex_vector_read_mul(4, u, A, j + v, m, 0x130);
	complex_vector_read_mul(4, a, A, j + v + half_m, m, 0x130);
	
	complex_vector_mul_bc(t, a, &omega);
	complex_vector_mul_bc(&t[V], &a[V], &omega);
	complex_vector_mul_bc(&t[2*V], &a[2*V], &omega);
	complex_vector_mul_bc(&t[3*V], &a[3*V], &omega);
	
	complex_vector_add(x, u, t);
	complex_vector_add(&x[V], &u[V], &t[V]);
	complex_vector_add(&x[2*V], &u[2*V], &t[2*V]);
	complex_vector_add(&x[3*V], &u[3*V], &t[3*V]);
	complex_vector_sub(y, u, t);
	complex_vector_sub(&y[V], &u[V], &t[V]);
	complex_vector_sub(&y[2*V], &u[2*V], &t[2*V]);
	complex_vector_sub(&y[3*V], &u[3*V], &t[3*V]);
	
	complex_vector_write_mul(4, x, A, j + v, m, 0x130);
	complex_vector_write_mul(4, y, A, j + v + half_m, m, 0x130);
      }
    }
  }

  count = 0;
  
  for(s = EFF4_LOG2V+1; s <= LOG2LEN; s++) {
    //
    // Late stage: our vectors will handle j directly, striding used only for w
    //

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);
    
    int k = 0;
    
    for(k = 0; k < FFT_LEN; k += m) {
      int v = 0;
	
      for(v = 0; v < half_m; v += EFF4_V) {
	printf("---\ns = %d k = %d v = %d\n---\n", s, k, v);
	
	complex_t omega[EFF4_V], a[EFF4_V], t[EFF4_V], u[EFF4_V], x[EFF4_V];
	  
	complex_vector_read_mul(4, omega, w, v * tab_step, tab_step, 0x4000);
	complex_vector_read_mul(4, u, A, k + v, 1, 0x130);
	complex_vector_read_mul(4, a, A, k + v + half_m, 1, 0x130);
	complex_vector_mul(t, a, omega);
	complex_vector_mul(&t[V], &a[V], &omega[V]);
	complex_vector_mul(&t[2*V], &a[2*V], &omega[2*V]);
	complex_vector_mul(&t[3*V], &a[3*V], &omega[3*V]);
	complex_vector_add(x, u, t);
	complex_vector_add(&x[V], &u[V], &t[V]);
	complex_vector_add(&x[2*V], &u[2*V], &t[2*V]);
	complex_vector_add(&x[3*V], &u[3*V], &t[3*V]);
	complex_vector_write_mul(4, x, A, k + v, 1, 0x130);
	complex_vector_sub(x, u, t);
	complex_vector_sub(&x[V], &u[V], &t[V]);
	complex_vector_sub(&x[2*V], &u[2*V], &t[2*V]);
	complex_vector_sub(&x[3*V], &u[3*V], &t[3*V]);
	complex_vector_write_mul(4, x, A, k + v + half_m, 1, 0x130);
      }
    }
  }
}

#define EFF8_LOG2V  (LOG2V+3)
#define EFF8_V      (1<<EFF8_LOG2V)
  
void fft_vectors_unroll8(complex_t A[])
{
  int s = 0, m = 0, half_m = 0, tab_step = 0;
  int count = 0;

  for(s = 1; s <= EFF8_LOG2V; s++) {
    //
    // Early stage: our vectors will handle k with striding by m
    //
    // if(half_m < V)
    //   m/2 < V <==> m < 2*V <==> 1<<s < 2*V <==> s < LOG2V + 1

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);

    int j = 0;
      
    for(j = 0; j < half_m; j++) {
      int v = 0;
      complex_t omega = complex_array_ref(w, j * tab_step, 0x4000); printf("\n");

      for(v = 0; v < FFT_LEN; v += EFF8_V*m) {
	printf("---\ns = %d j = %d v = %d\n---\n", s, j, v);
	
	complex_t a[EFF8_V], t[EFF8_V], u[EFF8_V], x[EFF8_V], y[EFF8_V];

	complex_vector_read_mul(8, u, A, j + v, m, 0x130);
	complex_vector_read_mul(8, a, A, j + v + half_m, m, 0x130);
	
	complex_vector_mul_bc(t, a, &omega);
	complex_vector_mul_bc(&t[V], &a[V], &omega);
	complex_vector_mul_bc(&t[2*V], &a[2*V], &omega);
	complex_vector_mul_bc(&t[3*V], &a[3*V], &omega);
	complex_vector_mul_bc(&t[4*V], &a[4*V], &omega);
	complex_vector_mul_bc(&t[5*V], &a[5*V], &omega);
	complex_vector_mul_bc(&t[6*V], &a[6*V], &omega);
	complex_vector_mul_bc(&t[7*V], &a[7*V], &omega);
	
	complex_vector_add(x, u, t);
	complex_vector_add(&x[V], &u[V], &t[V]);
	complex_vector_add(&x[2*V], &u[2*V], &t[2*V]);
	complex_vector_add(&x[3*V], &u[3*V], &t[3*V]);
	complex_vector_add(&x[4*V], &u[4*V], &t[4*V]);
	complex_vector_add(&x[5*V], &u[5*V], &t[5*V]);
	complex_vector_add(&x[6*V], &u[6*V], &t[6*V]);
	complex_vector_add(&x[7*V], &u[7*V], &t[7*V]);
	
	complex_vector_sub(y, u, t);
	complex_vector_sub(&y[V], &u[V], &t[V]);
	complex_vector_sub(&y[2*V], &u[2*V], &t[2*V]);
	complex_vector_sub(&y[3*V], &u[3*V], &t[3*V]);
	complex_vector_sub(&y[4*V], &u[4*V], &t[4*V]);
	complex_vector_sub(&y[5*V], &u[5*V], &t[5*V]);
	complex_vector_sub(&y[6*V], &u[6*V], &t[6*V]);
	complex_vector_sub(&y[7*V], &u[7*V], &t[7*V]);
	
	complex_vector_write_mul(8, x, A, j + v, m, 0x130);
	complex_vector_write_mul(8, y, A, j + v + half_m, m, 0x130);
      }
    }
  }

  count = 0;
  
  for(s = EFF8_LOG2V+1; s <= LOG2LEN; s++) {
    //
    // Late stage: our vectors will handle j directly, striding used only for w
    //

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);
    
    int k = 0;
    
    for(k = 0; k < FFT_LEN; k += m) {
      int v = 0;
	
      for(v = 0; v < half_m; v += EFF8_V) {
	printf("---\ns = %d k = %d v = %d\n---\n", s, k, v);
	
	complex_t omega[EFF8_V], a[EFF8_V], t[EFF8_V], u[EFF8_V], x[EFF8_V];
	  
	complex_vector_read_mul(8, omega, w, v * tab_step, tab_step, 0x4000);
	complex_vector_read_mul(8, u, A, k + v, 1, 0x130);
	complex_vector_read_mul(8, a, A, k + v + half_m, 1, 0x130);
	complex_vector_mul(t, a, omega);
	complex_vector_mul(&t[V], &a[V], &omega[V]);
	complex_vector_mul(&t[2*V], &a[2*V], &omega[2*V]);
	complex_vector_mul(&t[3*V], &a[3*V], &omega[3*V]);
	complex_vector_mul(&t[4*V], &a[4*V], &omega[4*V]);
	complex_vector_mul(&t[5*V], &a[5*V], &omega[5*V]);
	complex_vector_mul(&t[6*V], &a[6*V], &omega[6*V]);
	complex_vector_mul(&t[7*V], &a[7*V], &omega[7*V]);
	complex_vector_add(x, u, t);
	complex_vector_add(&x[V], &u[V], &t[V]);
	complex_vector_add(&x[2*V], &u[2*V], &t[2*V]);
	complex_vector_add(&x[3*V], &u[3*V], &t[3*V]);
	complex_vector_add(&x[4*V], &u[4*V], &t[4*V]);
	complex_vector_add(&x[5*V], &u[5*V], &t[5*V]);
	complex_vector_add(&x[6*V], &u[6*V], &t[6*V]);
	complex_vector_add(&x[7*V], &u[7*V], &t[7*V]);
	complex_vector_write_mul(8, x, A, k + v, 1, 0x130);
	complex_vector_sub(x, u, t);
	complex_vector_sub(&x[V], &u[V], &t[V]);
	complex_vector_sub(&x[2*V], &u[2*V], &t[2*V]);
	complex_vector_sub(&x[3*V], &u[3*V], &t[3*V]);
	complex_vector_sub(&x[4*V], &u[4*V], &t[4*V]);
	complex_vector_sub(&x[5*V], &u[5*V], &t[5*V]);
	complex_vector_sub(&x[6*V], &u[6*V], &t[6*V]);
	complex_vector_sub(&x[7*V], &u[7*V], &t[7*V]);
	complex_vector_write_mul(8, x, A, k + v + half_m, 1, 0x130);
      }
    }
  }
}

#ifdef RADIX4

void fft_radix4(complex_t A[])
{
  int s = 0, k = 0, j = 0, span = 0, quarter = 0, index_mult = 0;
  complex_t plus_i = COMPLEX_FROM_FLOAT(0.0f, 1.0f), minus_i = COMPLEX_FROM_FLOAT(0.0f, -1.0f);
  complex_t a0[V], a1[V], a2[V], a3[V], w1[V], w2[V], w3[V];
  complex_t t1[V], t2[V], t3[V], s0[V], s1[V], s2[V], s3[V];
  complex_t y0[V], y1[V], y2[V], y3[V];
  complex_t r3n[V], r3p[V];

  // for stage = 1 .. log4(N):
  //
  // 
  //
  
  for(s = 1; s <= LOG4LEN; s++) {
    span = 1<<(2 * s);  // 4^s
    quarter = span / 4;

    index_mult = FFT_LEN / span;
    
    // span    = 4^stage
    // quarter = span / 4

    // if quarter < V
    
    if(quarter < V) {
	  
      // early stage: small blocks, broadcast twiddle, strided across blocks
      // for j = 0 .. quarter-1:

      for(j = 0; j < quarter; j++) {
	    
	// w1j, w2j, w3j = twid1[j], twid2[j], twid3[j]   // scalars

	complex_t w1j = w[j * index_mult], w2j = w[j * 2*index_mult], w3j = w[j * 3*index_mult];
	int kb = 0;
	
	for(kb = 0; kb < FFT_LEN; kb += V*span) {
	  printf("--- \n0xB00B s = %d j = %x, kb = %x\n---\n", s, j, kb);
	
	  /*
	    VLD    a0, [a + j],            stride=span
	    VLD    a1, [a + j+quarter],    stride=span
	    VLD    a2, [a + j+2*quarter],  stride=span
	    VLD    a3, [a + j+3*quarter],  stride=span
	  */

	  complex_vector_read(a0, A, kb + j, span, 0x130);
	  complex_vector_read(a1, A, kb + j + quarter, span, 0x130);
	  complex_vector_read(a2, A, kb + j + 2*quarter, span, 0x130);
	  complex_vector_read(a3, A, kb + j + 3*quarter, span, 0x130);

	  /*
            t0 = a0
            VBCMUL t1, w1j, a1
            VBCMUL t2, w2j, a2
            VBCMUL t3, w3j, a3
	  */
	
	  complex_vector_mul_bc(t1, a1, &w1j);
	  complex_vector_mul_bc(t2, a2, &w2j);
	  complex_vector_mul_bc(t3, a3, &w3j);

	  /*
            VCADD s0, t0, t2    VCSUB s1, t0, t2
            VCADD s2, t1, t3    VCSUB s3, t1, t3
	  */

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);

	  /*
            VCADD y0, s0, s2
            VCSUB y2, s0, s2
            VROTNJ r3n, s3      VROTJ r3p, s3
            VCADD y1, s1, r3n
            VCADD y3, s1, r3p
	  */

	  complex_vector_add(y0, s0, s2);
	  complex_vector_sub(y2, s0, s2);
	  complex_vector_mul_bc(r3n, s3, &minus_i);
	  complex_vector_mul_bc(r3p, s3, &plus_i);
	  complex_vector_add(y1, s1, r3n);
	  complex_vector_add(y3, s1, r3p);

	  /*
            VST [a + j],            y0, stride=span
            VST [a + j+quarter],    y1, stride=span
            VST [a + j+2*quarter],  y2, stride=span
            VST [a + j+3*quarter],  y3, stride=span
	  */

	  complex_vector_write(y0, A, kb + j, span, 0x130);
	  complex_vector_write(y1, A, kb + j + quarter, span, 0x130);
	  complex_vector_write(y2, A, kb + j + 2*quarter, span, 0x130);
	  complex_vector_write(y3, A, kb + j + 3*quarter, span, 0x130);
	}
      }
    } else {
      // late stage: contiguous within a block, twiddle vectors

      // for j = 0, V, 2V, ... quarter-V:

      for(j = 0; j < quarter; j += V) {
	printf("--- \n0xDADA s = %d j = %x\n---\n", s, j);
	  
	complex_vector_read(w1, w, j * index_mult, index_mult, 0x10000);
	complex_vector_read(w2, w, j * 2*index_mult, 2*index_mult, 0x10000);
	complex_vector_read(w3, w, j * 3*index_mult, 3*index_mult, 0x10000);

	// for k = 0, span, 2*span, ... N-span:

	for(k = 0; k < FFT_LEN; k += span) {
	
	  printf("--- \n0xBEEF s = %d j = %x k = %x\n---\n", s, j, k);
	
	  /*
                VLD   a0, [a + k+j]
                VLD   a1, [a + k+j+quarter]
                VLD   a2, [a + k+j+2*quarter]
                VLD   a3, [a + k+j+3*quarter]
                VLD   w1, [twid1 + j]
                VLD   w2, [twid2 + j]
                VLD   w3, [twid3 + j]
	  */

	  complex_vector_read(a0, A, k + j, 1, 0x130);
	  complex_vector_read(a1, A, k + j + quarter, 1, 0x130);
	  complex_vector_read(a2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_read(a3, A, k + j + 3*quarter, 1, 0x130);
	  
	  /*
                t0 = a0
                VCMUL t1, w1, a1
                VCMUL t2, w2, a2
                VCMUL t3, w3, a3
	  */

	  complex_vector_mul(t1, w1, a1);
	  complex_vector_mul(t2, w2, a2);
	  complex_vector_mul(t3, w3, a3);

	  /*
                VCADD s0, t0, t2    VCSUB s1, t0, t2
                VCADD s2, t1, t3    VCSUB s3, t1, t3
	  */

	  complex_vector_add(s0, a0, t2);
	  complex_vector_sub(s1, a0, t2);
	  complex_vector_add(s2, t1, t3);
	  complex_vector_sub(s3, t1, t3);

	  /*
                VCADD y0, s0, s2
                VCSUB y2, s0, s2
                VROTNJ r3n, s3      VROTJ r3p, s3
                VCADD y1, s1, r3n
                VCADD y3, s1, r3p
	  */

	  complex_vector_add(y0, s0, s2);
	  complex_vector_sub(y2, s0, s2);
	  complex_vector_mul_bc(r3n, s3, &minus_i);
	  complex_vector_mul_bc(r3p, s3, &plus_i);
	  complex_vector_add(y1, s1, r3n);
	  complex_vector_add(y3, s1, r3p);
	  
	  /*
                VST [a + k+j],           y0
                VST [a + k+j+quarter],   y1
                VST [a + k+j+2*quarter], y2
                VST [a + k+j+3*quarter], y3
	  */

	  complex_vector_write(y0, A, k + j, 1, 0x130);
	  complex_vector_write(y1, A, k + j + quarter, 1, 0x130);
	  complex_vector_write(y2, A, k + j + 2*quarter, 1, 0x130);
	  complex_vector_write(y3, A, k + j + 3*quarter, 1, 0x130);

	}
      }
    }
    
    //STORE_FENCE   // required once per radix-4 stage, same cross-stage RAW hazard as before
  }
}
#endif

void store_complex_bin(const char *name, const char *mode, complex_t A[], int len, bool reverse)
{
  static uint32_t addr = 0;
  
  FILE *file = fopen(name, mode);

  if(file) {
    int i = 0;
  
    for(i = 0; i < len; i++) {
      int index = reverse ? bit_reverse(i) : i;
      complex_t a = A[index];
      
      // printbin(file, (int16_t) (a.real * (1<<PRECISION)));
      // printbin(file, (int16_t) (a.imag * (float) (1<<PRECISION)));
      //      print_bin(file, to_machine(&a));

      fprintf(file, "%.8x %.8x\n", addr, to_machine(&a));
      addr += sizeof(uint32_t);
    }

    fclose(file);
  } else
    printf("File %s could not be opened for writing.", name);
}

void store_reference(const char *name, complex_t A[], int len)
{
  FILE *file = fopen(name, "w");

  if(file) {
    int i = 0;
    
    for(i = 0; i < len; i++) {
      complex_t a = A[i];
      fprintf(file, "%.4X:=%.8X (S)\n", 0x800000 + i*4, to_machine(&a));
    }
    
    fclose(file);
  } else
    printf("File %s could not be opened for writing.", name);
}

int main()
{
  int i = 0;

  for(i = 0; i < FFT_LEN; i++)
    w[i] = COMPLEX_FROM_FLOAT(cosf(-i*2*pi/FFT_LEN), sinf(-i*2*pi/FFT_LEN));

  store_complex_bin("data_rom.txt", "w", w, FFT_LEN, false);

  for(i = 0; i < FFT_LEN; i++)
    printf("W[%d] = %.3f + i%.3f\n", i, TO_DOUBLE(w[i].real), TO_DOUBLE(w[i].imag));
  // printf("W[%d] = %.8x\n", i, to_machine(&w[i]));

#if TEST_FP16
  for(i = 0; i < FFT_LEN; i++) {
    printf("%.3f x %.3f = %.3f\n", TO_DOUBLE(fp16_from_int(i)), TO_DOUBLE(fp16_from_float(0.7f)), TO_DOUBLE(MUL(fp16_from_int(i), fp16_from_float(0.7f))));
    printf("%.3f x %.3f = %.3f\n", -TO_DOUBLE(fp16_from_int(i)), TO_DOUBLE(fp16_from_float(0.7f)), TO_DOUBLE(MUL(fp16_from_int(-i), fp16_from_float(0.7f))));
    printf("%.3f x %.3f = %.3f\n", TO_DOUBLE(fp16_from_int(i)), TO_DOUBLE(fp16_from_float(-0.7f)), TO_DOUBLE(MUL(fp16_from_int(i), fp16_from_float(-0.7f))));
  }

  part_t x = fp16_from_int(3);

  for(i = 0; i < FFT_LEN; i++) {
    printf("x = %.3f\n", TO_DOUBLE(x));
    x = MUL(x, fp16_from_float(0.9f));
  }

  x = fp16_from_int(1);
  
  for(i = 0; i < FFT_LEN; i++) {
    printf("x = %.3f\n", TO_DOUBLE(x));
    x = MUL(x, fp16_from_float(1.1f));
  }
  
  x = fp16_from_int(-1);
  
  for(i = 0; i < FFT_LEN; i++) {
    printf("x = %.3f\n", TO_DOUBLE(x));
    x = MUL(x, fp16_from_float(1.1f));
  }
  
  x = fp16_from_int(-1);
  
  for(i = 0; i < FFT_LEN; i++) {
    printf("x = %.3f\n", TO_DOUBLE(x));
    // x = ADD(x, fp16_from_float(0.07f));
    x = ADD(fp16_from_float(0.07f), x);
  }
  
  x = fp16_from_int(-1);
  
  for(i = 0; i < FFT_LEN; i++) {
    printf("x = %.3f\n", TO_DOUBLE(x));
    // x = ADD(x, fp16_from_float(0.07f));
    x = ADD(fp16_from_float(2.7f), x);
  }
  
  x = fp16_from_int(-1);
  
  for(i = 0; i < FFT_LEN; i++) {
    printf("x = %.3f\n", TO_DOUBLE(x));
    // x = ADD(x, fp16_from_float(0.07f));
    x = ADD(fp16_from_float(-2.7f), x);
  }
  
  for(i = 0; i < FFT_LEN; i++) {
    x = fp16_neg(fp16_from_int(2*i));
    printf("x = %.3f\n", TO_DOUBLE(x));
  }
  
  exit(0);
#endif
  
  for(i = 0; i < FFT_LEN; i++) {
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/32), 0.2f*sinf(i*2*pi/32));
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/32) + 0.4f, 0.2f*sinf(i*2*pi/32));
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/64), 0.2f*sinf(i*2*pi/64));
    // fft_data[i] = COMPLEX_FROM_FLOATLEX(0.1 + 0.2f*cosf(i*2*pi/64), 0.1 + 0.2f*sinf(i*2*pi/64));
    // fft_data[i] = COMPLEX_FROM_FLOAT(1.0f + 0.5f*cosf(i*2*pi/64) + 0.5f*cosf(i*2*pi/32), 1.0f);
    fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/16), 0.0f);
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.005f + 0.005f*cosf(i*2*pi/8) + 0.005f*cosf(i*2*pi/32), 0);
    //fft_data[i] = COMPLEX_FROM_FLOAT(0.02f, 0.0f);
    // fft_data[i] = COMPLEX_FROM_FLOAT(i & 1 ? 1.0f : -1.0f, 0.0f);
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.1, 0);
  }
  
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.3f + i%.3f\n", i, TO_DOUBLE(fft_data[i].real), TO_DOUBLE(fft_data[i].imag));
  
#ifdef RADIX4
  radix4_digit_reversal_permutation(fft_data);
#else
  bit_reversal_permutation(fft_data);
#endif
  
  store_complex_bin("data_rom.txt", "a+", fft_data, FFT_LEN, false);
  store_reference("input_reference.txt", fft_data, FFT_LEN);

  /*
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.8x\n", i, to_machine(&fft_data[i]));
  */
#ifdef RADIX4
  fft_radix4(fft_data);
#else
#if UNROLL < 2
  fft_with_vectors(fft_data);
#elif UNROLL < 4
  fft_vectors_unroll2(fft_data);
#elif UNROLL < 8
  fft_vectors_unroll4(fft_data);
#else
  fft_vectors_unroll8(fft_data);
#endif
#endif


  for(i = 0; i < FFT_LEN; i++)
    printf("Output[%d] = %.3f + i%.3f\n", i,
	   TO_DOUBLE(fft_data[i].real), TO_DOUBLE(fft_data[i].imag));
  
  store_reference("reference.txt", fft_data, FFT_LEN);
}
