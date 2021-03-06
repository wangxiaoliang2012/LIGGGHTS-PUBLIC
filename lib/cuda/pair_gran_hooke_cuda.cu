/* ----------------------------------------------------------------------
   LAMMPS - Large-scale Atomic/Molecular Massively Parallel Simulator 

   Original Version:
   http://lammps.sandia.gov, Sandia National Laboratories
   Steve Plimpton, sjplimp@sandia.gov 

   See the README file in the top-level LAMMPS directory. 

   ----------------------------------------------------------------------- 

   USER-CUDA Package and associated modifications:
   https://sourceforge.net/projects/lammpscuda/ 

   Christian Trott, christian.trott@tu-ilmenau.de
   Lars Winterfeld, lars.winterfeld@tu-ilmenau.de
   Theoretical Physics II, University of Technology Ilmenau, Germany 

   See the README file in the USER-CUDA directory. 

   This software is distributed under the GNU General Public License.
------------------------------------------------------------------------- */

#include <stdio.h>

#define _kn MY_AP(coeff1)  //[0]
#define _kt MY_AP(coeff1)  //[1]
#define _gamman MY_AP(coeff1) //[2]
#define _gammat MY_AP(coeff3) //[0]
#define _xmu MY_AP(coeff2) //[0]
#define _dampflag MY_AP(coeff2) //[1]

#include "pair_gran_hooke_cuda_cu.h"
#include "pair_gran_hooke_cuda_kernel_nc.cu"
#include <time.h>

void Cuda_PairGranHookeCuda_UpdateBuffer(cuda_shared_data* sdata, cuda_shared_neighlist* sneighlist)
{
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: before updateBuffer failed");
        int3 layout=getgrid(sneighlist->inum,7*sizeof(ENERGY_FLOAT));
	    dim3 threads(layout.z, 1, 1);
	    dim3 grid(layout.x, layout.y, 1);		
	    int size=(unsigned)(layout.y*layout.x)*7*sizeof(ENERGY_FLOAT);
		if(sdata->buffersize<size)
		{
			MYDBG(printf("Cuda_PairGranHookeCuda Resizing Buffer at %p with %i kB to\n",sdata->buffer,sdata->buffersize);)
			if(sdata->buffer!=NULL) cudaFree(sdata->buffer);
			cudaMalloc((void**)&sdata->buffer,size);
			sdata->buffersize=size;
			sdata->buffer_new++;
			MYDBG(printf("New buffer at %p with %i kB\n",sdata->buffer,sdata->buffersize);)
		}
		cudaMemcpyToSymbol(MY_CONST(buffer), & sdata->buffer, sizeof(int*)     );
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: updateBuffer failed");
}

void Cuda_PairGranHookeCuda_UpdateNmax(cuda_shared_data* sdata, cuda_shared_neighlist* sneighlist)
{
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: before updateNmax failed");
		cudaMemcpyToSymbol(MY_CONST(neighbor_maxlocal) , & sneighlist->firstneigh.dim[0]  , sizeof(unsigned) );
		//cudaMemcpyToSymbol(MY_CONST(firstneigh), & sneighlist->firstneigh.dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(ilist)     , & sneighlist->ilist     .dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(inum)      , & sneighlist->inum               , sizeof(int)  );
		cudaMemcpyToSymbol(MY_CONST(nlocal)    , & sdata->atom.nlocal             , sizeof(int)  );
		cudaMemcpyToSymbol(MY_CONST(nall)      , & sdata->atom.nall               , sizeof(int)  );
		cudaMemcpyToSymbol(MY_CONST(nmax)      , & sdata->atom.nmax               , sizeof(int)  );
		cudaMemcpyToSymbol(MY_CONST(numneigh)  , & sneighlist->numneigh  .dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(neighbors) , & sneighlist->neighbors  .dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(type)      , & sdata->atom.type      .dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(tag)       , & sdata->atom.tag       .dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(mask)      , & sdata->atom.mask      .dev_data, sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(f)         , & sdata->atom.f         .dev_data, sizeof(F_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(x)         , & sdata->atom.x         .dev_data, sizeof(X_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(x_type)    , & sdata->atom.x_type    .dev_data, sizeof(X_FLOAT4*) );
		cudaMemcpyToSymbol(MY_CONST(v_radius)  , & sdata->atom.v_radius  .dev_data, sizeof(V_FLOAT4*) );
		cudaMemcpyToSymbol(MY_CONST(omega_rmass),& sdata->atom.omega_rmass.dev_data,sizeof(V_FLOAT4*) );
		cudaMemcpyToSymbol(MY_CONST(torque)    , & sdata->atom.torque    .dev_data, sizeof(F_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(maxneighbors),&sneighlist->maxneighbors	 	  , sizeof(int) );
		cudaMemcpyToSymbol(MY_CONST(eatom)     , & sdata->atom.eatom     .dev_data, sizeof(ENERGY_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(vatom)     , & sdata->atom.vatom     .dev_data, sizeof(ENERGY_FLOAT*) );
		cudaMemcpyToSymbol(MY_CONST(debugdata) , & sdata->debugdata      		  , sizeof(int*) );
		cudaMemcpyToSymbol(MY_CONST(freeze_group_bit) , & sdata->pair.freeze_group_bit, sizeof(int)  );
		
		
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: updateNmax failed");
}


void Cuda_PairGranHookeCuda_Init(cuda_shared_data* sdata)
{
	// !! LAMMPS indexes atom types starting with 1 !!
	
	unsigned cuda_ntypes = sdata->atom.ntypes + 2;
	if(cuda_ntypes*cuda_ntypes > CUDA_MAX_TYPES2)
		printf("# CUDA: Cuda_PairGranHookeCuda_Init: you need %u types. this is more than %u "
		"(assumed at compile time). re-compile with -DCUDA_MAX_TYPES_PLUS_ONE=32 "
		"or ajust this in cuda_common.h\n", cuda_ntypes, CUDA_MAX_TYPES_PLUS_ONE-1);
	unsigned cuda_ntypes2 = cuda_ntypes * cuda_ntypes;
	unsigned n = sizeof(F_FLOAT) * cuda_ntypes2;
	
	F_FLOAT coeffs1[cuda_ntypes2];
	coeffs1[0]= (F_FLOAT) sdata->pair.coeff1[0][0];
	coeffs1[1]= (F_FLOAT) sdata->pair.coeff1[0][1];
	coeffs1[2]= (F_FLOAT) sdata->pair.coeff1[1][0];
	F_FLOAT coeffs3[cuda_ntypes2];
	coeffs3[0]= (F_FLOAT) sdata->pair.coeff1[1][1];
	F_FLOAT coeffs2[cuda_ntypes2];
	coeffs2[0]= (F_FLOAT) sdata->pair.coeff2[0][0];
	coeffs2[1]= (F_FLOAT) sdata->pair.coeff2[0][1];
	
	
	X_FLOAT box_size[3] =
	{
		sdata->domain.subhi[0] - sdata->domain.sublo[0],
		sdata->domain.subhi[1] - sdata->domain.sublo[1],
		sdata->domain.subhi[2] - sdata->domain.sublo[2]
	};
	//printf("n: %i %i\n",n,CUDA_MAX_TYPES2);
	cudaMemcpyToSymbol(MY_CONST(box_size)   , box_size                 , sizeof(X_FLOAT)*3);
	cudaMemcpyToSymbol(MY_CONST(cuda_ntypes), & cuda_ntypes            , sizeof(unsigned) );
	cudaMemcpyToSymbol(MY_CONST(coeff1)        , coeffs1                   , n                );
	cudaMemcpyToSymbol(MY_CONST(coeff2)        , coeffs2                   , n                );
	cudaMemcpyToSymbol(MY_CONST(coeff3)        , coeffs3                   , n                );
	cudaMemcpyToSymbol(MY_CONST(virial)     , &sdata->pair.virial.dev_data   , sizeof(ENERGY_FLOAT*)  );
	cudaMemcpyToSymbol(MY_CONST(eng_vdwl)     , &sdata->pair.eng_vdwl.dev_data   , sizeof(ENERGY_FLOAT*)  );
	cudaMemcpyToSymbol(MY_CONST(periodicity), sdata->domain.periodicity, sizeof(int)*3    );
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: init failed");
}



void Cuda_PairGranHookeCuda(cuda_shared_data* sdata, cuda_shared_neighlist* sneighlist, int eflag, int vflag,int eflag_atom,int vflag_atom)
{
	
	//if(sdata->atom.update_nmax) 
		Cuda_PairGranHookeCuda_UpdateNmax(sdata,sneighlist);
	//if(sdata->atom.update_nlocal) 		
	{
		cudaMemcpyToSymbol(MY_CONST(nlocal)  , & sdata->atom.nlocal        , sizeof(int)  );
		cudaMemcpyToSymbol(MY_CONST(nall)    , & sdata->atom.nall          , sizeof(int)  );
	}		
	//if(sdata->buffer_new)
		Cuda_PairGranHookeCuda_UpdateBuffer(sdata,sneighlist);
	
	BindXTypeTexture(sdata);
	BindVRadiusTexture(sdata);
	BindOmegaRmassTexture(sdata);

	int sharedperproc=0;
	if(eflag) sharedperproc+=1;
	if(vflag) sharedperproc+=6;

	int3 layout=getgrid(sneighlist->inum,sharedperproc*sizeof(ENERGY_FLOAT),128);
	dim3 threads(layout.z, 1, 1);
	dim3 grid(layout.x, layout.y, 1);

	// initialize only on first call
	static  short init=0;
	if(! init)
	{
		init = 1;
		Cuda_PairGranHookeCuda_Init(sdata);
	}
	
	MYDBG( printf("# CUDA: Cuda_PairGranHookeCuda: kernel start eflag: %i vflag: %i config: %i %i %i %i\n",eflag,vflag,grid.x,grid.y, threads.x,sharedperproc*sizeof(ENERGY_FLOAT)*threads.x); )
	
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: (no binning) pre pair lj cut Kernel problems before kernel invocation");
	PairGranHookeCuda_Kernel<<<grid, threads,sharedperproc*sizeof(ENERGY_FLOAT)*threads.x>>> (eflag, vflag,eflag_atom,vflag_atom,(int**)sneighlist->firstneigh.dev_data,sneighlist->binned_id
	,(F_FLOAT) sdata->pair.coeff1[0][0],(F_FLOAT) sdata->pair.coeff1[1][0],(F_FLOAT) sdata->pair.coeff1[1][1],(F_FLOAT) sdata->pair.coeff2[0][0]);
	cudaThreadSynchronize();
	CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: (no binning) pair lj cut Kernel execution failed");
	
	if(eflag||vflag) 
	{
		int n=grid.x*grid.y;
		grid.x=sharedperproc;
		grid.y=1;
		threads.x=256;
		MY_AP(PairVirialCompute_reduce)<<<grid,threads,threads.x*sizeof(ENERGY_FLOAT)>>>(n);
		cudaThreadSynchronize();
		CUT_CHECK_ERROR("Cuda_PairGranHookeCuda: (no binning) virial compute Kernel execution failed");
	}

	MYDBG( printf("# CUDA: Cuda_PairGranHookeCoulLongCuda: kernel done\n"); )
	
}


#undef _kn
#undef _kt
#undef _gamman
#undef _gammat
#undef _xmu
#undef _dampflag


