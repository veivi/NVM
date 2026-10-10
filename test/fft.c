#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <assert.h>

// #define USE_FLOATS  1

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

#ifndef PRECISION
#define PRECISION 12
#endif

#define FFT_LEN     (1<<LOG2LEN)
#define pi          ((float) M_PI)

#ifdef USE_FLOATS
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

#else

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

#define SATURATE(a, p) (a) < -1L<<(p+(16-p)) ? 
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

uint32_t to_fixed_point(complex_t *a)
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
  printf("%.4x ~%.8x | ", base + index*4, to_fixed_point(&value));
  return value;
} 

void complex_array_set(complex_t value, complex_t array[], int index, int base)
{
  assert(index < FFT_LEN);
  
  printf("%.4x:=%.8x | ", base + index*4, to_fixed_point(&value));
  array[index] = value;
} 

void complex_vector_print(complex_t value[])
{
  int i = 0;
  for(i = 0; i < V; i++)
    printf("%.8x (%.3f +i%.3f), ", to_fixed_point(&value[i]), TO_DOUBLE(value[i].real), TO_DOUBLE(value[i].imag));
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

void print_bin(FILE *file, uint32_t a)
{
  int i = 0;
  while(i < 8*sizeof(a)) {
    fprintf(file, "%c", a & 0x80000000UL ? '1' : '0');
    a <<= 1;
    i++;
  }
}

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
      //      print_bin(file, to_fixed_point(&a));

      fprintf(file, "%.8x %.8x\n", addr, to_fixed_point(&a));
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
      fprintf(file, "%.4X:=%.8X (S)\n", 0xFF0000 + i*4, to_fixed_point(&a));
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
    printf("W[%d] = %.8x\n", i, to_fixed_point(&w[i]));
  
  for(i = 0; i < FFT_LEN; i++) {
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/32), 0.2f*sinf(i*2*pi/32));
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/32) + 0.2f*sinf(i*2*pi/32), 0);
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/64), 0.2f*sinf(i*2*pi/64));
    // fft_data[i] = COMPLEX_FROM_FLOATLEX(0.1 + 0.2f*cosf(i*2*pi/64), 0.1 + 0.2f*sinf(i*2*pi/64));
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.1 + 0.2f*cosf(i*2*pi/64) + 0.2f*cosf(i*2*pi/32), 0);
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.2f*cosf(i*2*pi/16), 0.0f);
    fft_data[i] = COMPLEX_FROM_FLOAT(0.005f + 0.005f*cosf(i*2*pi/8) + 0.005f*cosf(i*2*pi/32), 0);
    //fft_data[i] = COMPLEX_FROM_FLOAT(0.02f, 0.0f);
    // fft_data[i] = COMPLEX_FROM_FLOAT(i & 1 ? 1.0f : -1.0f, 0.0f);
    // fft_data[i] = COMPLEX_FROM_FLOAT(0.1, 0);
  }
  
#ifdef RADIX4
  radix4_digit_reversal_permutation(fft_data);
#else
  bit_reversal_permutation(fft_data);
#endif
  
  store_complex_bin("data_rom.txt", "a+", fft_data, FFT_LEN, false);
  store_reference("input_reference.txt", fft_data, FFT_LEN);

  /*
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.3f + i%.3f\n", i, TO_DOUBLE(fft_data[i].real), TO_DOUBLE(fft_data[i].imag));
  
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.8x\n", i, to_fixed_point(&fft_data[i]));
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
