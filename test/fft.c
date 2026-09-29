#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <math.h>

#define LOG2LEN     8
#define FFT_LEN     (1<<LOG2LEN)
#define LOG2V       3
#define V           (1<<LOG2V)
#define PRECISION   12
#define pi          ((float) M_PI)

typedef struct complex {
  float real, imag;
} complex_t;

#define COMPLEX(r, i) (complex_t) { .real = r, .imag = i }
#define COMPLEX_ADD(a, b) (complex_t) { (a).real + (b).real, (a).imag + (b).imag }
#define COMPLEX_SUB(a, b) (complex_t) { (a).real - (b).real, (a).imag - (b).imag }
#define COMPLEX_MUL(a, b) (complex_t) { (a).real*(b).real-(a).imag*(b).imag, (a).real*(b).imag+(a).imag*(b).real }
#define COMPLEX_ABS(a) sqrtf((a).real*(a).real + (a).imag*(a).imag)

complex_t fft_data[FFT_LEN];
complex_t w[FFT_LEN];

uint32_t to_fixed_point(complex_t *a)
{
  int32_t result = (int32_t) (a->real * (float) (1<<PRECISION));
  result = result<<16;
  result |= ((int32_t) (a->imag * (float) (1<<PRECISION))) & 0xFFFF;
  return result;
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

complex_t complex_array_ref(complex_t array[], int index, int base)
{
  complex_t value = array[index];
  printf("%.4x ~%.8x | ", base + index*4, to_fixed_point(&value));
  return value;
} 

void complex_array_set(complex_t value, complex_t array[], int index, int base)
{
  printf("%.4x:=%.8x | ", base + index*4, to_fixed_point(&value));
  array[index] = value;
} 

void complex_vector_print(complex_t value[])
{
  int i = 0;
  for(i = 0; i < V; i++)
    printf("%.8x (%.3f +i%.3f), ", to_fixed_point(&value[i]), value[i].real, value[i].imag);
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
  int count = 0;

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
      complex_t omega = complex_array_ref(w, j * tab_step, 0x1000); printf("\n");

      for(v = 0; v < FFT_LEN; v += V*m) {
	complex_t a[V], t[V], u[V], x[V], y[V];

	complex_vector_read(u, A, j + v, m, 0x130);
	complex_vector_read(a, A, j + v + half_m, m, 0x130);
	complex_vector_mul_bc(t, a, &omega);
	complex_vector_add(x, u, t);
	complex_vector_sub(y, u, t);
	complex_vector_write(x, A, j + v, m, 0x130);
	complex_vector_write(y, A, j + v + half_m, m, 0x130);
	printf("Early %d\n", count++);
      }
    }
  }

  count = 0;
  
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
	complex_t omega[V], a[V], t[V], u[V], x[V];
	  
	complex_vector_read(omega, w, v * tab_step, tab_step, 0x1000);
	complex_vector_read(u, A, k + v, 1, 0x130);
	complex_vector_read(a, A, k + v + half_m, 1, 0x130);
	complex_vector_mul(t, a, omega);
	complex_vector_add(x, u, t);
	complex_vector_write(x, A, k + v, 1, 0x130);
	complex_vector_sub(x, u, t);
	complex_vector_write(x, A, k + v + half_m, 1, 0x130);
	printf("Late %d\n", count++);
      }
    }
  }
}

#define EFF_LOG2V  (LOG2V+1)
#define EFF_V      (1<<EFF_LOG2V)
  
void fft_vectors_unroll2(complex_t A[])
{
  int s = 0, m = 0, half_m = 0, tab_step = 0;
  int count = 0;

  for(s = 1; s <= EFF_LOG2V; s++) {
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
      complex_t omega = complex_array_ref(w, j * tab_step, 0x1000); printf("\n");

      for(v = 0; v < FFT_LEN; v += EFF_V*m) {
	complex_t a[EFF_V], t[EFF_V], u[EFF_V], x[EFF_V], y[EFF_V];

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
	printf("Early %d\n", count++);
      }
    }
  }

  count = 0;
  
  for(s = EFF_LOG2V+1; s <= LOG2LEN; s++) {
    //
    // Late stage: our vectors will handle j directly, striding used only for w
    //

    m = 1<<s;
    half_m = m/2;
    tab_step = 1<<(LOG2LEN - s);
    
    int k = 0;
    
    for(k = 0; k < FFT_LEN; k += m) {
      int v = 0;
	
      for(v = 0; v < half_m; v += EFF_V) {
	complex_t omega[EFF_V], a[EFF_V], t[EFF_V], u[EFF_V], x[EFF_V];
	  
	complex_vector_read_mul(2, omega, w, v * tab_step, tab_step, 0x1000);
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

	printf("Late %d\n", count++);
      }
    }
  }
}

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
  FILE *file = fopen(name, mode);

  if(file) {
    int i = 0;
  
    for(i = 0; i < len; i++) {
      int index = reverse ? bit_reverse(i) : i;
      complex_t a = A[index];
      
      // printbin(file, (int16_t) (a.real * (1<<PRECISION)));
      // printbin(file, (int16_t) (a.imag * (float) (1<<PRECISION)));
      print_bin(file, to_fixed_point(&a));
      fprintf(file, "\n");
    }

    fclose(file);
  } else
    printf("File %s could not be opened for writing.", name);
}

int main()
{
  int i = 0;

  printf("Blob.\n");
  
  for(i = 0; i < FFT_LEN; i++)
    w[i] = COMPLEX(cosf(i*2*pi/FFT_LEN), -sinf(i*2*pi/FFT_LEN));

  store_complex_bin("data_rom.txt", "w", w, FFT_LEN, false);

  for(i = 0; i < FFT_LEN; i++)
    printf("W[%d] = %.8x\n", i, to_fixed_point(&w[i]));
  
  for(i = 0; i < FFT_LEN; i++)
    // fft_data[i] = COMPLEX(0.02f*cosf(i*2*pi/8), 0.02f*sinf(i*2*pi/8));
    // fft_data[i] = COMPLEX(0.2f*cosf(i*2*pi/16), 0.0f);
    fft_data[i] = COMPLEX(0.03f + 0.05f*cosf(i*2*pi/8) + 0.05f*cosf(i*2*pi/32), 0);
    // fft_data[i] = COMPLEX(0.02f, 0.0f);
    // fft_data[i] = COMPLEX(i & 1 ? 1.0f : -1.0f, 0.0f);
  
  bit_reversal_permutation(fft_data);
  
  store_complex_bin("data_rom.txt", "a+", fft_data, FFT_LEN, false);
  
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.3f + i%.3f\n", i, fft_data[i].real, fft_data[i].imag);
  
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.8x\n", i, to_fixed_point(&fft_data[i]));
  
  // fft(fft_data);
  // fft_with_vectors(fft_data);
  fft_vectors_unroll2(fft_data);
  
  for(i = 0; i < FFT_LEN; i++)
    printf("Output[%d] = %.3f + i%.3f (%.3f)\n", i,
	   fft_data[i].real, fft_data[i].imag, COMPLEX_ABS(fft_data[i]));
}
