#-----------------------------------------------------------------------------
# Rebuild the pongo image
#  Required if the 'KONG_IMAGE' has been rebuilt w/o changing its tag version
#-----------------------------------------------------------------------------
# KONG_IMAGE=jeromeguillaume/kong-saxon:3.7.1.1 pongo build

#------------------------------------------------
# Execute the tests with the Kong standard image
#   Doesn't work with the Saxon tests
#------------------------------------------------
# KONG_IMAGE=kong/kong-gateway pongo run --lpath=$PWD/spec/common

#-------------------------------------------------------------
# Execute the tests with the customized Kong image with Saxon
#-------------------------------------------------------------
KONG_IMAGE=jeromeguillaume/kong-saxon:3.7.1.1 pongo run --lpath=$PWD/spec/common

#---------------------------------------------------------
# Loop tests
#---------------------------------------------------------
#COUNTER=0
#while true
#do
#  ((COUNTER++))
#  echo "Exectuion #$COUNTER"
#	KONG_IMAGE=kong/kong-gateway pongo run --lpath=$PWD/spec/common
#done
