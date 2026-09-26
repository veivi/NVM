#include <stdio.h>
#include <math.h>

#define  LOG2LEN     6
#define  FFT_LEN      (1<<LOG2LEN)
#define  LOG2V       3
#define  V           (1<<LOG2V)
#define  pi          ((float) M_PI)

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

void complex_vector_read(complex_t value[], complex_t array[], int index, int stride)
{
  int i = 0;
  for(i = 0; i < V; i++)
    value[i] = array[index + i*stride];
}

void complex_vector_write(const complex_t value[], complex_t array[], int index, int stride)
{
  int i = 0;
  for(i = 0; i < V; i++)
    array[index + i*stride] = value[i];
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

  bit_reversal_permutation(A);
  
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

  bit_reversal_permutation(A);
  
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
      complex_t omega = w[j * tab_step];

      for(v = 0; v < FFT_LEN; v += V*m) {
	complex_t a[V], t[V], u[V], x[V];

	complex_vector_read(a, A, j + v + half_m, m);
	complex_vector_read(u, A, j + v, m);
	complex_vector_mul_bc(t, a, &omega);
	complex_vector_add(x, u, t);
	complex_vector_write(x, A, j + v, m);
	complex_vector_sub(x, u, t);
	complex_vector_write(x, A, j + v + half_m, m);
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
	complex_t omega[V], a[V], t[V], u[V], x[V];
	  
	complex_vector_read(omega, w, v * tab_step, tab_step);
	complex_vector_read(a, A, k + v + half_m, 1);
	complex_vector_mul(t, a, omega);
	complex_vector_read(u, A, k + v, 1);
	complex_vector_add(x, u, t);
	complex_vector_write(x, A, k + v, 1);
	complex_vector_sub(x, u, t);
	complex_vector_write(x, A, k + v + half_m, 1);
      }
    }
  }
}

void printbin(int16_t a)
{
  int i = 0;
  while(i < 8*sizeof(a)) {
    printf("%c", a & 0x8000 ? '1' : '0');
    a <<= 1;
    i++;
  }
}

int main()
{
  int i = 0;

  printf("Blob.\n");
  
  for(i = 0; i < FFT_LEN; i++)
    w[i] = COMPLEX(cosf(i*2*pi/FFT_LEN), -sinf(i*2*pi/FFT_LEN));
  
  for(i = 0; i < FFT_LEN; i++) {
    int16_t real = (int16_t) (w[i].real * (1<<14)), imag = (w[i].imag * (float) (1<<14));
    // printf("W[i] = %d + i%d\n", real, imag);
    printbin(real);
    printbin(imag);
    printf("\n");
  }
    
  for(i = 0; i < FFT_LEN; i++)
    // fft_data[i] = COMPLEX(cosf(i*2*pi/8), sinf(i*2*pi/8));
    fft_data[i] = COMPLEX(1.0f + sinf(i*2*pi/8) + sinf(i*2*pi/32), 0);
    // fft_data[i] = COMPLEX(1.0f, 0.0f);
    // fft_data[i] = COMPLEX(i & 1 ? 1.0f : -1.0f, 0.0f);
  
  for(i = 0; i < FFT_LEN; i++)
    printf("Input[%d] = %.3f + i%.3f\n", i, fft_data[i].real, fft_data[i].imag);
  
  fft_with_vectors(fft_data);
  // fft(fft_data);
  for(i = 0; i < FFT_LEN; i++)
    printf("Output[%d] = %.3f + i%.3f (%.3f)\n", i,
	   fft_data[i].real, fft_data[i].imag, COMPLEX_ABS(fft_data[i]));
}
