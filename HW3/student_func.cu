/* Udacity Homework 3
   HDR Tone-mapping

  Background HDR
  ==============

  A High Definition Range (HDR) image contains a wider variation of intensity
  and color than is allowed by the RGB format with 1 byte per channel that we
  have used in the previous assignment.  

  To store this extra information we use single precision floating point for
  each channel.  This allows for an extremely wide range of intensity values.

  In the image for this assignment, the inside of church with light coming in
  through stained glass windows, the raw input floating point values for the
  channels range from 0 to 275.  But the mean is .41 and 98% of the values are
  less than 3!  This means that certain areas (the windows) are extremely bright
  compared to everywhere else.  If we linearly map this [0-275] range into the
  [0-255] range that we have been using then most values will be mapped to zero!
  The only thing we will be able to see are the very brightest areas - the
  windows - everything else will appear pitch black.

  The problem is that although we have cameras capable of recording the wide
  range of intensity that exists in the real world our monitors are not capable
  of displaying them.  Our eyes are also quite capable of observing a much wider
  range of intensities than our image formats / monitors are capable of
  displaying.

  Tone-mapping is a process that transforms the intensities in the image so that
  the brightest values aren't nearly so far away from the mean.  That way when
  we transform the values into [0-255] we can actually see the entire image.
  There are many ways to perform this process and it is as much an art as a
  science - there is no single "right" answer.  In this homework we will
  implement one possible technique.

  Background Chrominance-Luminance
  ================================

  The RGB space that we have been using to represent images can be thought of as
  one possible set of axes spanning a three dimensional space of color.  We
  sometimes choose other axes to represent this space because they make certain
  operations more convenient.

  Another possible way of representing a color image is to separate the color
  information (chromaticity) from the brightness information.  There are
  multiple different methods for doing this - a common one during the analog
  television days was known as Chrominance-Luminance or YUV.

  We choose to represent the image in this way so that we can remap only the
  intensity channel and then recombine the new intensity values with the color
  information to form the final image.

  Old TV signals used to be transmitted in this way so that black & white
  televisions could display the luminance channel while color televisions would
  display all three of the channels.
  

  Tone-mapping
  ============

  In this assignment we are going to transform the luminance channel (actually
  the log of the luminance, but this is unimportant for the parts of the
  algorithm that you will be implementing) by compressing its range to [0, 1].
  To do this we need the cumulative distribution of the luminance values.

  Example
  -------

  input : [2 4 3 3 1 7 4 5 7 0 9 4 3 2]
  min / max / range: 0 / 9 / 9

  histo with 3 bins: [4 7 3]

  cdf : [4 11 14]


  Your task is to calculate this cumulative distribution by following these
  steps.

*/

#include "utils.h"
#include "stdio.h"

// Parallel reduce function. op is a pointer to a function which takes two
// floating point parameters and returns a single floating point value.
// The d_workArea array is used to store intermediate computations - the final
// value of the reduce operation will be found in the zeroth location.
__global__ void reduce(const float* const d_logLuminance, const float* d_workArea,
		       float (*op)(float, float), const size_t numRows, const size_t numCols)
{
    const int2 thread_2D_pos = make_int2( blockIdx.x * blockDim.x + threadIdx.x,
					  blockIdx.y * blockDim.y + threadIdx.y);
    if (thread_2D_pos.x >= numCols || thread_2D_pos.y >= numRows)
	return;
	
    const int thread_1D_pos = thread_2D_pos.y * numCols + thread_2D_pos.x;
    
    unsigned int s = (numRows * numCols)/2; // half the array size
    // Do the first computation, putting the result into the work area
    d_workArea[thread_1D_pos] = op(d_logLuminance[thread_1D_pos],
				   d_logLuminance[thread_1D_pos + s]);
    
    for (s>>=1; s > 0; s>>=1) {
	if (thread_1D_pos < s && s == starts){
	    d_workArea[thread_1D_pos] = op(d_workArea[thread_1D_pos], d_workArea[thread_1D_pos + s]);
	}
	__syncthreads();
    }
    
}

// Device function to compute max value of two floats
__device__ float d_max(float a, float b)
{
    return a > b ? a : b;
}

// Device function to compute min value of two floats
__device__ float d_min(float a, float b)
{
    return a > b ? b : a;
}

void your_histogram_and_prefixsum(const float* const d_logLuminance,
                                  unsigned int* const d_cdf,
                                  float &min_logLum,
                                  float &max_logLum,
                                  const size_t numRows,
                                  const size_t numCols,
                                  const size_t numBins)
{
  //TODO
  /*Here are the steps you need to implement
    1) find the minimum and maximum value in the input logLuminance channel
       store in min_logLum and max_logLum
    2) subtract them to find the range
    3) generate a histogram of all the values in the logLuminance channel using
       the formula: bin = (lum[i] - lumMin) / lumRange * numBins
    4) Perform an exclusive scan (prefix sum) on the histogram to get
       the cumulative distribution of luminance values (this should go in the
       incoming d_cdf pointer which already has been allocated for you)       */

    // Allocate device memory for reduce return values
    // This should be a power of 2 for reduce to work properly
    const dim3 blockSize(32,32,1);
    const dim3 gridSize(ceil((float)numCols/blockSize.x),
			ceil((float)numRows/blockSize.x), 1);
    
    // Allocate a work area half the size of the 1D array which stores the
    // log luminance values
    const int workSize = (sizeof(float) * numRows * numCols)/2;
    const float* d_workArea;
    checkCudaErrors(cudaMalloc(&d_workArea, workSize));
    
    // Get the max luminance value by calling reduce with the min function
    reduce<<<gridSize, blockSize>>>(d_logLuminance, d_workArea, d_max,
				    numRows, numCols);
    // Copy the result of the reduce operation into the variable given by
    // copying the first memory location in the work area.
    checkCudaErrors(cudaMemcpy((void*) &max_logLum, d_workArea, sizeof(float),
    			       cudaMemcpyDeviceToHost));


    
    // Get the minimum luminance value by calling reduce with the min function
    reduce<<<gridSize, blockSize>>>(d_logLuminance, d_workArea, d_min,
				    numRows, numCols);
    // Copy the result of the reduce operation into the variable given by
    // copying the first memory location in the work area.
    /* checkCudaErrors(cudaMemcpy((void*) &min_logLum, d_workArea, sizeof(float), */
    /* 			       cudaMemcpyDeviceToHost)); */

    printf("Max luminance: %f, Min luminance: %f\n", max_logLum, min_logLum);
}
