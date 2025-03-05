#!/bin/bash
#

### possible simulation scenarios
# 1. NCODA, ANALYSIS, 8-day forecast with or without gempak/gzip
# 2. NCODA, ANALYSIS, 1-day forecast with or without gempak/gzip
# 3. Run with smaller HYCOM (900 procs)
# 4. Any single job (no dependencies, COMOUT set and ready)
# 5. Restart at any job (no dependencies on finished jobs, like rocoto-restart)
# 6. Forcing staged
# 7. NCODA only
# 8. Restart Forecast at checkpoint (nwges?)
# 9. ..
#
### configurable variables
# 1. DCOMxxxx (for development obs)
# 2. project root (different codes)
# 3. GDAS/GFS location
# 4. ..
#
#####

if [ $# -ne 2 ] 
then
  echo "USAGE: $0 <configname> <YYYYMMDD>"
  exit -2
fi

configname=$1
today=$2
now=$(date +%Y%m%d_%H%M%S)
if [ ! -s ./$configname ]
then
  echo cannot find $configname
  exit -2
fi
. ./$configname

# other vars not in config but can be modified on occasion
export account=RTOFS-DEV
export simulation=${simulation:-sim}
export sim=${sim:-zz}
#export tmproot=/lfs/h2/emc/ptmp/$LOGNAME/$simulation
export tmproot=/lfs/h2/emc/stmp/$LOGNAME/$simulation

# below now set in config file
#export projectroot=/lfs/h2/emc/eib/noscrub/Dan.Iredell/currprod
#export comroot=/lfs/h2/emc/eib/noscrub/$LOGNAME/COMDIR
#export inputroot=/lfs/h1/ops/canned/dcom
#export inputroot=/lfs/h2/emc/couple/noscrub/zulema.garraffo/dcom
#export inputroot=/lfs/h2/emc/eib/noscrub/dan.iredell/dcom/prod

echo
echo projectroot $projectroot
echo tmproot $tmproot
echo simulation $simulation
echo

batchloc=$tmproot/batchscripts
mkdir -p $batchloc

export KEEPDATA=YES

#######################################################

export PROJECTdir=$projectroot
. $PROJECTdir/versions/run.ver
export ver=$(echo $rtofs_glo_ver | cut -d. -f1-2)
# versions not needed
#export envvar_ver=1.0
#export prod_envir_ver=2.0.6
#export prod_util_ver=2.0.13
echo 
echo projectroot $projectroot
echo rtofs_glo_ver $rtofs_glo_ver
echo ver $ver
echo
#exit

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load bufr_dump/${bufr_dump_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load gempak/${gempak_ver}
module load cdo/${cdo_ver}
module list

#override COMs
export COMtmp=$comroot

# Set some run environment variables.
export SENDCOM=YES
export SENDDBN=NO
export model_ver=$rtofs_glo_ver
export projID=NC-${model_ver} #      `basename $PROJECTdir`

export cyc=00
export cycle=t${cyc}z
export envir=prod # prod or para or canned

export HOMErtofs=${PROJECTdir}
export HOMErtofs_glo=$HOMErtofs

# HERA mods - no gribbing or cdo outputs
#export for_opc=NO
#export grib_1hrly=NO
#--
####export rtofs_glo_ver=v${model_ver}

# Set system/model vars
export RUN=rtofs
export NET=rtofs
export modID=glo
#export ver=v2.2 # in $projectroot/run.ver
export inputgrid=navy_0.08
#### if realtime reset fcstdays_step2=0
#### or if hurricane reset fcstdays_step2=4
. $PROJECTdir/parm/${RUN}_${modID}.${inputgrid}.config
export fcstdays=`expr ${fcstdays_step1} + ${fcstdays_step2}`

echo forecast days -- $analdays + $fcstdays_step1 + $fcstdays_step1
echo gzip $rungzip rungempak $rungempak

# let it default
#export NWROOT=$UTILROOT
export COMROOT=${COMtmp}/$envir/com/$NET/$ver
echo COMROOT $COMROOT

# observational TANKS -- these can to be changed... check envir
export DCOMROOT=$inputroot
export DCOMINAMSR=$DCOMROOT
export DCOMINSSH=$DCOMROOT
export DCOMINSSS=$DCOMROOT
export DCOMINSST=$DCOMROOT
export DCOMINHFR=$DCOMROOT
export TANK=$DCOMROOT

# where should we find GDAS/GFS surface flux file (should we override GETGES_COM)
# export envir=
# export envirges=
# export GETGES_COM=

# very important: redefinition of the default date (PDY !!!)
# if PDY is defined here, it will not be reset by setpdy utility.
export PDY=$today
export PDYm1=`$NDATE -24 ${PDY}'00' | cut -c1-8`
export myDATAROOT=$tmproot/${projID}/$PDY
mkdir -p ${myDATAROOT}
#export myCOMROOT=${COMtmp}/$envir/com/$NET/$ver
export myCOMROOT=${COMtmp}/$envir/com
mkdir -p ${myCOMROOT}

#override COMIN and COMINm1
export COMIN=$COMROOT/$RUN.$PDY
export COMINm1=$COMROOT/$RUN.$PDYm1

# Test restart file in hindcast
#hindcast=NO
#if [ $hindcast = YES ] 
#then
#  RESTdir=${COMtmp}/rtofs/nwges/rtofs.`$NDATE -24 ${PDY}'00' | cut -c1-8`
#  RESTfile=${RESTdir}/rtofs_glo.t${cyc}z.restart_f24
#  if ! [ -s ${RESTfile}.a ] || ! [ -s  ${RESTfile}.b ]
#  then
#      echo "LAUNCHER ERROR: No restart found."
#      echo "                FILE:  ${RESTfile}.[ab] "    
##      exit -3
#   fi
#fi

# Make logs directory if necessary.
test -d $COMtmp/logs/$today || mkdir -p $COMtmp/logs/$today

# Write out some info.
echo "LAUNCHER INFO: run: ${projID}, cycle: t${cyc}z, PDY=${PDY}."

pid=$$
cd ${myDATAROOT}
cd $COMtmp/logs/$today

# Submit the jobs.

# area for testing only one set of jobs
testjustthisjob=0
analysisanditspost=0
forecast1anditspost=0
if [ $configname == rtofs.v2.4.4.config ]; then
testjustthisjob=1
analysisanditspost=1
forecast1anditspost=0
fi
if [ $configname == rtofs.v2.4.5.config ]; then
testjustthisjob=1
analysisanditspost=1
forecast1anditspost=0
fi
if [ $configname == runops.config ]; then
testjustthisjob=1
analysisanditspost=0
forecast1anditspost=0
fi
if [ $configname == PROD.config ]; then
testjustthisjob=1
analysisanditspost=1
fi
# not coded yet:   forecast2anditspost=0
if [ $testjustthisjob -eq 1 ]
then

if [ $analysisanditspost -eq 1 ]
then

########
# Submit Analysis
export jobid=jrtofs_analysis.$now
mkdir -p ${myDATAROOT}/$jobid
cat << EOF_analysis > $batchloc/rtofs.analysis.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_ANALYSIS
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=15:ncpus=120:mpiprocs=120
#PBS -q dev
#PBS -l walltime=01:29:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load netcdf/${netcdf3_ver}
module load hdf5/${hdf5_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1800

export FI_OFI_RXM_BUFFER_SIZE=128000
export FI_OFI_RXM_RX_SIZE=64000
export OMP_NUM_THREADS=1
$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS

EOF_analysis

jobid_analysis=$(qsub $batchloc/rtofs.analysis.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis is submitted - jobid $jobid_analysis
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#Submit analysis post
export jobid=jrtofs_analysis_post
mkdir -p ${myDATAROOT}/$jobid

cat << EOF_analysis_post > $batchloc/rtofs.analysis_post.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_ANAL_POST
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=4:mem=120GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_POST

EOF_analysis_post

jobid_analpost=$(qsub -W depend=afterok:$jobid_analysis $batchloc/rtofs.analysis_post.$pid)
#jobid_analpost=$(qsub $batchloc/rtofs.analysis_post.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis post is submitted - jobid $jobid_analpost
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#Submit analysis grib2 post
export jobid=jrtofs_analysis_grib_post
export NN=01
export job=${RUN}_${modID}_analysis_grib_post_${projID}.${NN}
cat << EOF_analysis_grib_post > $batchloc/rtofs.analysis_grib_post.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_ANAL_GRIB_POST
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=11:mem=16GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=11

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_GRIB2_POST

EOF_analysis_grib_post

jobid_analgribpost=$(qsub -W depend=afterok:$jobid_analysis $batchloc/rtofs.analysis_grib_post.$pid)
#jobid_analgribpost=$(qsub $batchloc/rtofs.analysis_grib_post.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis grib post is submitted - jobid $jobid_analgribpost
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis grib post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

##########
#Submit analysis gzip
if [ $rungzip -eq 1 ]
then
export jobid=jrtofs_gzip_00
mkdir -p ${myDATAROOT}/$jobid
cat << EOF_gzip00 > $batchloc/rtofs.gzip00.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_GZIP00
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=12:mem=22GB
#PBS -q dev
#PBS -l walltime=00:40:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=12

export CYC=00
export cyc=00

$HOMErtofs/jobs/JRTOFS_GLO_GZIP

EOF_gzip00

jobid_gzip00=$(qsub -W depend=afterok:$jobid_analysis $batchloc/rtofs.gzip00.$pid)
#jobid_gzip00=$(qsub $batchloc/rtofs.gzip00.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO gzip00 is submitted - jobid $jobid_gzip00
else
  echo 'LAUNCHER ERROR: RTOFS-GLO gzip00 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
fi # rungzip
exit
fi #analysisanditspost
##########

if [ $forecast1anditspost -eq 1 ]
then
#############
# Submit Forecast step1
export jobid=jrtofs_forecast_step1.$now
mkdir -p ${myDATAROOT}/$jobid
cat << EOF_forecast_step1 > $batchloc/rtofs.forecast_step1.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_FORECAST_STEP1
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=15:ncpus=120:mpiprocs=120
#PBS -q dev
#PBS -l walltime=03:00:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load netcdf/${netcdf3_ver}
module load hdf5/${hdf5_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1800

export FI_OFI_RXM_BUFFER_SIZE=128000
export FI_OFI_RXM_RX_SIZE=64000
export OMP_NUM_THREADS=1
$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_STEP1

EOF_forecast_step1

jobid_forecast_step1=$(qsub $batchloc/rtofs.forecast_step1.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast step1 is submitted - jobid $jobid_forecast_step1
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast step1 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#check for fcstdays_step1 number - may change the NN count
#Submit forecast step1 grib_post and post
for NN in 01 02 03
do
  export job=jrtofs_forecast_grib_post.${NN}
  export jobid=$job
  export NN
cat << EOF_forecast_step1_grib_post > $batchloc/rtofs.forecast_step1_grib_post.$NN.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_FORECAST_STEP1_GRIB_POST_D$NN
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=11:mem=16GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=11

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_GRIB2_POST

EOF_forecast_step1_grib_post

jobid_forecast_grib_post=$(qsub -W depend=afterok:$jobid_forecast_step1 $batchloc/rtofs.forecast_step1_grib_post.$NN.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast grib post is submitted - jobid $jobid_forecast_grib_post
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast grib post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

done

for NN in 01 02 03 04
do
  export job=jrtofs_forecast_post.${NN}
  export jobid=$job
  export NN
cat << EOF_forecast_step1_post > $batchloc/rtofs.forecast_step1_post.$NN.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_FORECAST_STEP1_POST_D$NN
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=4:mem=120GB
#PBS -q dev
#PBS -l walltime=00:55:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_POST

EOF_forecast_step1_post

jobid_forecast_post=$(qsub -W depend=afterok:$jobid_forecast_step1 $batchloc/rtofs.forecast_step1_post.$NN.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast post is submitted - jobid $jobid_forecast_post
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
done

#############
#Submit forecast step1 gzip (issue - gzip for forecasts only work with 4-day forecasts)
if [ $rungzip -eq 1 ]
then
export jobid=jrtofs_gzip_06
mkdir -p ${myDATAROOT}/$jobid
cat << EOF_gzip06 > $batchloc/rtofs.gzip06.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_GZIP06
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=22:mem=22GB
#PBS -q dev
#PBS -l walltime=00:40:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=22

export CYC=06
export cyc=06

$HOMErtofs/jobs/JRTOFS_GLO_GZIP

EOF_gzip06

jobid_gzip06=$(qsub -W depend=afterok:$jobid_forecast_step1 $batchloc/rtofs.gzip06.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO gzip06 is submitted - jobid $jobid_gzip06
else
  echo 'LAUNCHER ERROR: RTOFS-GLO gzip06 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
fi # rungzip
exit
fi #forecast1anditspost

#############
# justthisjob but not anditspost

#HERE
################################
#Submit analysis post
export jobid=jrtofs_analysis_post
mkdir -p ${myDATAROOT}/$jobid

cat << EOF_analysis_post > $batchloc/rtofs.analysis_post.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_ANAL_POST
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=4:mem=120GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list 

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_POST

EOF_analysis_post

jobid_analpost=$(qsub $batchloc/rtofs.analysis_post.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis post is submitted - jobid $jobid_analpost
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#Submit analysis grib2 post
export jobid=jrtofs_analysis_grib_post
export NN=01
export job=${RUN}_${modID}_analysis_grib_post_${projID}.${NN}
cat << EOF_analysis_grib_post > $batchloc/rtofs.analysis_grib_post.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_ANAL_GRIB_POST
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=11:mem=16GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=11

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_GRIB2_POST

EOF_analysis_grib_post

jobid_analgribpost=$(qsub $batchloc/rtofs.analysis_grib_post.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis grib post is submitted - jobid $jobid_analgribpost
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis grib post not submitted at host '`hostname`' at '`date` "error is $#"
  exit 
fi

################################

echo justthisonejob jobs

exit
fi #testjustthisjob

echo DATAROOT is $myDATAROOT
echo

#determine if a specific job runs (this will be hairy)
# runqc=1        if runonejob=0 or runonejob=1 and theonejob=ncoda_qc
# runpolar=1     if runonejob=0 or runonejob=1 and theonejob=polar_var
# runglbl=1      if runonejob=0 or runonejob=1 and theonejob=glbl_var
# runhycom=1     if runonejob=0 or runonejob=1 and theonejob=hycom_var
# runncodainc=1  if runonejob=0 or runonejob=1 and theonejob=ncoda_inc
# runincup=1     if runonejob=0 or runonejob=1 and theonejob=incup
#
#other flags
# runda=0        skip da jobs and change dependency on analysis_pre
#

runda=1
if [ $runda -eq 1 ]
then

#############
jobname=rtofs_ncoda_qc
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_ncoda_qc > $batchloc/rtofs.ncoda_qc.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=12:mem=90GB
#PBS -q dev
#PBS -l walltime=00:59:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load bufr_dump/${bufr_dump_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=12

$HOMErtofs/jobs/JRTOFS_GLO_NCODA_QC

EOF_ncoda_qc

jobid_qc=$(qsub $batchloc/rtofs.ncoda_qc.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO ncoda qc is submitted - jobid $jobid_qc
else
  echo 'LAUNCHER ERROR: RTOFS-GLO ncoda qc not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

if [ $configname ==  rtofs.v2.5.bm.config ]; then
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
echo just this QC job
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
exit -8
fi

skip2dvar=0
if [ $skip2dvar -eq 0 ]
then
#global var
jobname=rtofs_glbl_var
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_ncoda_glbl_var > $batchloc/rtofs.glblvar.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=72:mem=60GB
#PBS -q dev
#PBS -l walltime=00:59:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=72

$HOMErtofs/jobs/JRTOFS_GLO_NCODA_GLBL_VAR

EOF_ncoda_glbl_var

jobid_glbl=$(qsub -W depend=afterok:$jobid_qc $batchloc/rtofs.glblvar.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO global var is submitted - jobid $jobid_glbl
else
  echo 'LAUNCHER ERROR: RTOFS-GLO glbl var not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#polar var
jobname=rtofs_polar_var
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_ncoda_polar_var > $batchloc/rtofs.polarvar.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=24:mem=4GB
#PBS -q dev
#PBS -l walltime=00:59:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=24

$HOMErtofs/jobs/JRTOFS_GLO_NCODA_POLAR_VAR

EOF_ncoda_polar_var

jobid_polar=$(qsub -W depend=afterok:$jobid_qc $batchloc/rtofs.polarvar.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO polar var is submitted - jobid $jobid_polar
else
  echo 'LAUNCHER ERROR: RTOFS-GLO polar var not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
fi #skip2dvar

# 6/27 - changed excl to exclhost
#hycom var
jobname=rtofs_hycom_var
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_ncoda_hycom_var > $batchloc/rtofs.hycomvar.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=3:ncpus=120
#PBS -l place=excl
#PBS -q dev
#PBS -l walltime=01:59:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=360

$HOMErtofs/jobs/JRTOFS_GLO_NCODA_HYCOM_VAR

EOF_ncoda_hycom_var

jobid_hycom=$(qsub -W depend=afterok:$jobid_qc $batchloc/rtofs.hycomvar.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO hycom var is submitted - jobid $jobid_hycom
else
  echo 'LAUNCHER ERROR: RTOFS-GLO hycom var not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

# Submit NCODA increment
jobname=rtofs_ncoda_inc
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_ncoda_inc > $batchloc/rtofs.ncoda.inc.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=1:mem=50GB
#PBS -q dev
#PBS -l walltime=00:30:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1

$HOMErtofs/jobs/JRTOFS_GLO_NCODA_INC

EOF_ncoda_inc

jobid_ncoda_inc=$(qsub -W depend=afterok:$jobid_hycom $batchloc/rtofs.ncoda.inc.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO ncoda inc is submitted - jobid $jobid_ncoda_inc
else
  echo 'LAUNCHER ERROR: RTOFS-GLO ncoda_inc not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

########
# Submit NCODA increment update
jobname=rtofs_incup
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_ncoda_incup > $batchloc/rtofs.incup.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=15:ncpus=120:mpiprocs=120
#PBS -q dev
#PBS -l walltime=00:59:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1800

export FI_OFI_RXM_BUFFER_SIZE=128000
export FI_OFI_RXM_RX_SIZE=64000
export OMP_NUM_THREADS=1
$HOMErtofs/jobs/JRTOFS_GLO_INCUP

EOF_ncoda_incup

jobid_incup=$(qsub -W depend=afterok:$jobid_ncoda_inc $batchloc/rtofs.incup.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO incup is submitted - jobid $jobid_incup
else
  echo 'LAUNCHER ERROR: RTOFS-GLO incup not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

if [ $analdays -eq 0 ]
then
  echo analdays = 0 so no analysis and no further jobs
  exit -4
fi

fi # runda=1

#############
jobname=rtofs_analysis_pre
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid

cat << EOF_analysis_pre > $batchloc/rtofs.analysis_pre.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=1:mem=10GB
#PBS -q dev
#PBS -l walltime=00:50:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cfp/${cfp_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_PRE

EOF_analysis_pre

if [ $runda -eq 1 ]
then
jobid_preanal=$(qsub -W depend=afterok:$jobid_qc $batchloc/rtofs.analysis_pre.$pid)
else
jobid_preanal=$(qsub $batchloc/rtofs.analysis_pre.$pid)
fi
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO pre-analysis is submitted - jobid $jobid_preanal
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis pre not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi


#echo 
#echo
if [ $configname == bugfixes.config ]; then
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
echo no more jobs for $configname
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
exit -8
fi

#if [ $configname == synobs.config ]; then
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#echo just this QC job
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#exit -8
#fi

if [ $configname == PROD.config ]; then
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
echo no more jobs for $configname
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
exit -8
fi

#if [ $configname == test.v2.4.0.config ]; then
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#echo no more jobs for $configname
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#exit -8
#fi

#echo
#echo
#exit

########
# Submit Analysis
jobname=rtofs_analysis
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_analysis > $batchloc/rtofs.analysis.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=15:ncpus=120:mpiprocs=120
#PBS -q dev
#PBS -l walltime=01:29:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load netcdf/${netcdf3_ver}
module load hdf5/${hdf5_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1800

export FI_OFI_RXM_BUFFER_SIZE=128000
export FI_OFI_RXM_RX_SIZE=64000
export OMP_NUM_THREADS=1
$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS

EOF_analysis

if [ $runda -eq 1 ]
then
jobid_analysis=$(qsub -W depend=afterok:$jobid_incup:$jobid_preanal $batchloc/rtofs.analysis.$pid)
else
jobid_analysis=$(qsub -W depend=afterok:$jobid_preanal $batchloc/rtofs.analysis.$pid)
fi
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis is submitted - jobid $jobid_analysis
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#Submit analysis post
jobname=rtofs_analysis_post
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid

cat << EOF_analysis_post > $batchloc/rtofs.analysis_post.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=4:mem=120GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_POST

EOF_analysis_post

jobid_analpost=$(qsub -W depend=afterok:$jobid_analysis $batchloc/rtofs.analysis_post.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis post is submitted - jobid $jobid_analpost
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#Submit analysis grib2 post
export NN=01
jobname=rtofs_analysis_grib_post.d${NN}
export jobid=$jobname.$pid
export job=$jobname
cat << EOF_analysis_grib_post > $batchloc/rtofs.analysis_grib_post.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=11:mem=16GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=11

$HOMErtofs/jobs/JRTOFS_GLO_ANALYSIS_GRIB2_POST

EOF_analysis_grib_post

jobid_analgribpost=$(qsub -W depend=afterok:$jobid_analysis $batchloc/rtofs.analysis_grib_post.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO analysis grib post is submitted - jobid $jobid_analgribpost
else
  echo 'LAUNCHER ERROR: RTOFS-GLO analysis grib post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

##########
#Submit analysis gzip
if [ $rungzip -eq 1 ]
then
jobname=rtofs_gzip_00
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_gzip00 > $batchloc/rtofs.gzip00.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=12:mem=22GB
#PBS -q dev
#PBS -l walltime=00:40:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=12

export CYC=00
export cyc=00

$HOMErtofs/jobs/JRTOFS_GLO_GZIP

EOF_gzip00

jobid_gzip00=$(qsub -W depend=afterok:$jobid_analysis $batchloc/rtofs.gzip00.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO gzip00 is submitted - jobid $jobid_gzip00
else
  echo 'LAUNCHER ERROR: RTOFS-GLO gzip00 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
fi # rungzip

xfer2dogwood=0
if [ $xfer2dogwood -eq 1 ]
then
export jobid=jrtofs_transfer00z
export job=$jobid
mkdir -p ${myDATAROOT}/$jobid
cat << EOF_transfer00z > $batchloc/rtofs.transfer00z.$pid
#!/bin/bash
#PBS -N $simulation.RTOFS_transfer00z
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=9
#PBS -q dev_transfer
#PBS -l walltime=06:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module list

export COMROOT=$myCOMROOT/rtofs.$PDY
export DATAROOT=$myDATAROOT

cd $myDATAROOT/$jobid
ssh dan.iredell@ddxfer "mkdir -p $COMROOT"
echo "scp -p $COMROOT/rtofs_glo.t00z.n-24.restart.a dan.iredell@ddxfer:$COMROOT" > cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n-24.arch* dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n-24.restart*[bez] dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n-06.restart.a dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n-06.arch* dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n-06.restart*[bez] dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n00.restart.a dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n00.arch* dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy
echo "scp -p $COMROOT/rtofs_glo.t00z.n00.restart*[bez] dan.iredell@ddxfer:$COMROOT" >> cmdfile.copy

chmod +x cmdfile.copy
mpiexec -np 9 --cpu-bind verbose,core cfp ./cmdfile.copy > copy.out
echo cfp returned $?
ssh dan.iredell@ddxfer "touch $COMROOT/nowcast.mirror.complete"

EOF_transfer00z

jobid_transfer00z=$(qsub -W depend=afterok:$jobid_gzip00 $batchloc/rtofs.transfer00z.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO transfer00z is submitted - jobid $jobid_transfer00z
else
  echo 'LAUNCHER ERROR: RTOFS-GLO transfer00z not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
fi # xfer2dogwood

#if [ $configname == testbed.v2.4.config ]; then
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#echo just this QC job
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#exit -8
#fi
if [ $configname == testbed.v2.3.config ]; then
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
echo just this QC job
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
exit -8
fi

if [ $configname == bugfixes.config ]; then
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
echo no more jobs for $configname
echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
exit -8
fi

#if [ $configname == synobs.config ]; then
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#echo no more jobs for $configname
#echo NOTICE NOTICE NOTICE NOTICE NOTICE NOTICE
#exit -8
#fi

##########
#Check for forecast jobs
if [ $fcstdays_step1 -eq 0 ]
then
  echo fcstdays_step1 = 0 so no forecast step1 and no further jobs
  exit -4
fi
#############
#Submit pre forecast1
jobname=rtofs_fcst1_pre
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid

cat << EOF_fcst1_pre > $batchloc/rtofs.fcst1_pre.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=1:mem=10GB
#PBS -q dev
#PBS -l walltime=00:50:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cfp/${cfp_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_STEP1_PRE

EOF_fcst1_pre

jobid_prefcst1=$(qsub -W depend=afterok:$jobid_preanal $batchloc/rtofs.fcst1_pre.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO fcst1 pre is submitted - jobid $jobid_prefcst1
else
  echo 'LAUNCHER ERROR: RTOFS-GLO fcst1 pre not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

########
# Submit Forecast step1
jobname=rtofs_forecast_step1
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_forecast_step1 > $batchloc/rtofs.forecast_step1.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=15:ncpus=120:mpiprocs=120
#PBS -q dev
#PBS -l walltime=03:00:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load netcdf/${netcdf3_ver}
module load hdf5/${hdf5_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1800

export FI_OFI_RXM_BUFFER_SIZE=128000
export FI_OFI_RXM_RX_SIZE=64000
export OMP_NUM_THREADS=1
$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_STEP1

EOF_forecast_step1

jobid_forecast_step1=$(qsub -W depend=afterok:$jobid_analysis:$jobid_prefcst1 $batchloc/rtofs.forecast_step1.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast step1 is submitted - jobid $jobid_forecast_step1
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast step1 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#############
#check for fcstdays_step1 number - may change the NN count
#Submit forecast step1 grib_post and post
fcst_grib_post_days=$fcstdays_step1
if [ $fcstdays_step1 -eq 4 ];then fcst_grib_post_days=3;fi
for NN in $(seq -w 01 01 $fcst_grib_post_days)
do
  jobname=rtofs_forecast_grib_post.d${NN}
  export jobid=$jobname.$pid
  export job=$jobname
  export NN
cat << EOF_forecast_step1_grib_post > $batchloc/rtofs.forecast_step1_grib_post.$NN.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=11:mem=16GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=11

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_GRIB2_POST

EOF_forecast_step1_grib_post

jobid_forecast_grib_post=$(qsub -W depend=afterok:$jobid_forecast_step1 $batchloc/rtofs.forecast_step1_grib_post.$NN.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast grib post is submitted - jobid $jobid_forecast_grib_post
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast grib post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

done

for NN in $(seq -w 01 01 $fcstdays_step1)
do
  jobname=rtofs_forecast_post.d${NN}
  export jobid=$jobname.$pid
  export job=$jobname
  export NN
cat << EOF_forecast_step1_post > $batchloc/rtofs.forecast_step1_post.$NN.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=4:mem=120GB
#PBS -q dev
#PBS -l walltime=00:50:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_POST

EOF_forecast_step1_post

jobid_forecast_post=$(qsub -W depend=afterok:$jobid_forecast_step1 $batchloc/rtofs.forecast_step1_post.$NN.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast post is submitted - jobid $jobid_forecast_post
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
done

#############
#Submit forecast step1 gzip
if [ $rungzip -eq 1 ]
then
jobname=rtofs_gzip_06
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_gzip06 > $batchloc/rtofs.gzip06.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=22:mem=22GB
#PBS -q dev
#PBS -l walltime=00:40:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=22

export CYC=06
export cyc=06

$HOMErtofs/jobs/JRTOFS_GLO_GZIP

EOF_gzip06

jobid_gzip06=$(qsub -W depend=afterok:$jobid_forecast_step1 $batchloc/rtofs.gzip06.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO gzip06 is submitted - jobid $jobid_gzip06
else
  echo 'LAUNCHER ERROR: RTOFS-GLO gzip06 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
fi # rungzip

##########
#Submit gempak
##########
if [[ $rungempak -eq 1 && $fcstdays_step1 -ge 3 ]]
then
for reg in alaska bering watl
do
jobname=rtofs_global_gempak_${reg}
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_gempak > $batchloc/rtofs.gempak.$reg.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=24:mem=4GB
#PBS -q dev
#PBS -l walltime=00:10:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load gempak/${gempak_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=24

if [ $reg == watl ]
then
  export instr=west_atl
  export outstr=$reg
else
  export instr=$reg
  export outstr=$reg
fi

$HOMErtofs/jobs/JRTOFS_GLO_GEMPAK

EOF_gempak

jobid_gempak=$(qsub -W depend=afterok:$jobid_forecast_grib_post $batchloc/rtofs.gempak.$reg.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO $reg gempak is submitted - jobid $jobid_gempak
else
  echo 'LAUNCHER ERROR: RTOFS-GLO $reg gempak not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
done
fi # rungempak


#Check for forecast step2 jobs
if [ $fcstdays_step2 -eq 0 ]
then
  echo fcstdays_step2 = 0 so no forecast step2 and no further jobs
  exit -4
fi
#############
#Submit pre forecast2
jobname=rtofs_fcst2_pre
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid

cat << EOF_fcst2_pre > $batchloc/rtofs.fcst2_pre.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=1:mem=5GB
#PBS -q dev
#PBS -l walltime=00:30:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cfp/${cfp_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_STEP2_PRE

EOF_fcst2_pre

jobid_prefcst2=$(qsub -W depend=afterok:$jobid_prefcst1 $batchloc/rtofs.fcst2_pre.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO fcst2 pre is submitted - jobid $jobid_prefcst2
else
  echo 'LAUNCHER ERROR: RTOFS-GLO fcst2 pre not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

########
# Submit Forecast step2
jobname=rtofs_forecast_step2
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_forecast_step2 > $batchloc/rtofs.forecast_step2.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter:exclhost,select=15:ncpus=120:mpiprocs=120
#PBS -q dev
#PBS -l walltime=03:00:00
#PBS -l debug=true
#PBS -V

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load craype/${craype_ver}
module load intel/${intel_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module load netcdf/${netcdf3_ver}
module load hdf5/${hdf5_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1800

export FI_OFI_RXM_BUFFER_SIZE=128000
export FI_OFI_RXM_RX_SIZE=64000
export OMP_NUM_THREADS=1
$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_STEP2

EOF_forecast_step2

jobid_forecast_step2=$(qsub -W depend=afterok:$jobid_forecast_step1:$jobid_prefcst2 $batchloc/rtofs.forecast_step2.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast step2 is submitted - jobid $jobid_forecast_step2
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast step2 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

#Submit forecast step2 gzip (issue - gzip for forecasts only work with 4-day forecasts)
if [ $rungzip -eq 1 ]
then
jobname=rtofs_gzip_12
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_gzip12 > $batchloc/rtofs.gzip12.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=22:mem=22GB
#PBS -q dev
#PBS -l walltime=00:40:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cray-mpich/${cray_mpich_ver}
module load cfp/${cfp_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=22

export CYC=12
export cyc=12

$HOMErtofs/jobs/JRTOFS_GLO_GZIP

EOF_gzip12

jobid_gzip12=$(qsub -W depend=afterok:$jobid_forecast_step2 $batchloc/rtofs.gzip12.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO gzip12 is submitted - jobid $jobid_gzip12
else
  echo 'LAUNCHER ERROR: RTOFS-GLO gzip12 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
# save all forecast2 post production jobids
allforecast2postjobs=$jobid_gzip12
fi # rungzip

#############
#check for fcstdays_step2 number - may change the NN count
#Submit forecast step2 grib_post and post
jobname=rtofs_forecast_post_2
export jobid=$jobname.$pid
export job=$jobname
#mkdir -p ${myDATAROOT}/$jobid
cat << EOF_forecast_post_2 > $batchloc/rtofs.forecast_post_2.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A RTOFS-DEV
#PBS -l place=vscatter,select=1:ncpus=4:mem=8GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_POST_2

EOF_forecast_post_2

jobid_forecast_post2=$(qsub -W depend=afterok:$jobid_forecast_step2 $batchloc/rtofs.forecast_post_2.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast post2 is submitted - jobid $jobid_forecast_post2
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast post2 not submitted at host '`hostname`' at '`date` "error is $#"
  exit
# save all forecast2 post production jobids
allforecast2postjobs=${allforecast2postjobs}:${jobid_forecast_post2}
fi

for NN in 04
do
  jobname=rtofs_forecast_grib_post.d${NN}
  export jobid=$jobname.$pid
  export job=$jobname
  export NN
cat << EOF_forecast_step2_grib_post > $batchloc/rtofs.forecast_step2_grib_post.$NN.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=11:mem=16GB
#PBS -q dev
#PBS -l walltime=02:00:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=11

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_GRIB2_POST

EOF_forecast_step2_grib_post

jobid_forecast_grib_post=$(qsub -W depend=afterok:$jobid_forecast_step2 $batchloc/rtofs.forecast_step2_grib_post.$NN.$pid)

if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast grib post is submitted - jobid $jobid_forecast_grib_post
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast grib post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi
# save all forecast2 post production jobids
allforecast2postjobs=${allforecast2postjobs}:${jobid_forecast_grib_post}
done

#post
for NN in 05 06 07 08
do
  jobname=rtofs_forecast_post.d${NN}
  export jobid=$jobname.$pid
  export job=$jobname
  export NN
cat << EOF_forecast_step2_post > $batchloc/rtofs.forecast_step2_post.$NN.$pid
#!/bin/bash
#PBS -N $jobname
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=4:mem=120GB
#PBS -q dev
#PBS -l walltime=00:50:00
#PBS -l debug=true
#PBS -V

source ${HOMErtofs_glo}/versions/run.ver

module purge
module load envvar
module load prod_envir
module load prod_util
module load PrgEnv-intel/${PrgEnv_intel_ver}
module load intel/${intel_ver}
module load craype/${craype_ver}
module load cray-pals/${cray_pals_ver}
module load cfp/${cfp_ver}
module load hdf5/${hdf5_ver}
module load netcdf/${netcdf4_ver}
module load wgrib2/${wgrib2_ver}
module load libjpeg/${libjpeg_ver}
module load grib_util/${grib_util_ver}
module load cdo/${cdo_ver}
module list

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=4

$HOMErtofs/jobs/JRTOFS_GLO_FORECAST_POST

EOF_forecast_step2_post

jobid_forecast_post=$(qsub -W depend=afterok:$jobid_forecast_step2 $batchloc/rtofs.forecast_step2_post.$NN.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO forecast post is submitted - jobid $jobid_forecast_post
else
  echo 'LAUNCHER ERROR: RTOFS-GLO forecast post not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

# save all forecast2 post production jobids
allforecast2postjobs=${allforecast2postjobs}:${jobid_forecast_post}

done

##########
#Submit check outputs
if [ $checkoutputs -ne 1 ]
then
   echo Not checking outputs
   exit
fi

cat << EOF_checkoutputs > $batchloc/rtofs.checkoutputs.$pid
#!/bin/bash
#PBS -N rtofs_check_outputs
#PBS -j oe
#PBS -A $account
#PBS -l place=vscatter,select=1:ncpus=1
#PBS -q dev
#PBS -l walltime=00:08:00
#PBS -l debug=true
#PBS -V

export COMROOT=$myCOMROOT
export DATAROOT=$myDATAROOT
export NPROCS=1

echo myCOMROOT $myCOMROOT
echo RUN $RUN
echo ver $ver
echo NET $NET
echo PDY $PDY

# $myCOMROOT/$RUN/$ver/$NET.$PDY

#            analysis  forecast1   forecast2
# netcdf files 558
# grb2 files 55
# tgz files 478

#                 netcdf
# format        
# analysis          91
# forecast1 (4)
# forecast2 (4)
# TOTAL
# 
# forecast (1)


#         format                          analysis    forecast1  forecast2    TOTAL
# netcdf  rtofs_glo_[23]??_[nf][01]*.nc   91          280        187          558
# grb2    rtofs_glo.t00z.[nf]*.grb2       11           33         11           55
# tgz     rtofs_glo.t00z.[nf]*.tgz        61          209        208          478

set -x

ncdfcount=\$(ls $myCOMROOT/$RUN/$ver/$NET.$PDY/*.nc | wc -l)
grb2count=\$(ls $myCOMROOT/$RUN/$ver/$NET.$PDY/*.grb2 | wc -l)
tgzcount=\$(ls $myCOMROOT/$RUN/$ver/$NET.$PDY/*.tgz | wc -l)

echo COUNTS in $myCOMROOT/$RUN/$ver/$NET.$PDY
echo netcdf -- \$ncdfcount
echo grib2  -- \$grb2count
echo tgz -- \$tgzcount

EOF_checkoutputs

jobid_check_outputs=$(qsub -W depend=afterok:$allforecast2postjobs $batchloc/rtofs.checkoutputs.$pid)
if [ $# -gt 0 ]
then
  echo LAUNCHER: RTOFS-GLO check outputs is submitted - jobid $jobid_check_outputs
else
  echo 'LAUNCHER ERROR: RTOFS-GLO check outputs not submitted at host '`hostname`' at '`date` "error is $#"
  exit
fi

exit

################################3
################################3
################################3


# jobs left to code
# -----------------
# check outputs (nc, grb2, tgz)
# archive (archive can only run if gzip and check-outputs run)


# get PBS cards from /lfs/h2/emc/eib/noscrub/Dan.Iredell/currprod/ecf
# and tools/batchscripts/ncoda*nodep scripts

#note - forecast1 and forecast2 days!!!  f1=(0 1 4); f2=(1, 4) 

exit 0
