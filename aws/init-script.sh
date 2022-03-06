#!/bin/bash
MAIN_REGION="eu-west-1"
DR_REGION="eu-central-1"
MAIN_STATE_BUCKET="s3-states-$1-tools"
DR_STATE_BUCKET="s3-states-$1-tools-dr"
RESOURCES_BUCKET="$1-tools-ec2-resources-bucket"
SUFFIX_DR="-dr"
PROFILE="terraform-tools-$1"

set -e

###
# Check parameters
###
if [[ "$#" -ne 1 ]] && [[ "$#" -ne 2 ]]; then
        echo "Illegal number of parameters"
        echo "Usage :"
        echo "  ./init.sh <ENVIRONMENT>"
        echo "Optional :"
        echo "  Generate DR work directory : ./init.sh <ENVIRONMENT> dr"
        echo "  Generate SSH keys : ./init.sh gen-ssh-keys"
        exit
fi

if [[ "$1" != "dev" ]] && [[ "$1" != "uat" ]] && [[ "$1" != "prod" ]] && [[ "$1" != "gen-ssh-keys" ]]; then
	echo "$1 illegal parameter"
	echo "Allowed arguments : dev | uat | prod | gen-ssh-keys"
	exit
fi

if ! [[ -z "$2" ]] && [[ "$2" != "dr" ]]; then
    echo "$2 illegal parameter"
    echo "Allowed argument : dr"
    echo "  Generate DR environment : ./init.sh <ENVIRONMENT> dr"
    exit
fi

#Aplication & function name
STACK_NAME=$(echo $PWD | rev | cut -d'/' -f 2 | rev)
STACK_FUNCTION=$(echo $PWD | rev | cut -d'/' -f 1 | rev)

###s
# Generate SSH keys
###
if [[ "$1" == "gen-ssh-keys"  ]]; then
    echo 'Generating SSH keys.'
    KEY_NAME="tools-"$STACK_NAME"-"$1
    mkdir $PWD/ssh-keys
    ssh-keygen -b 4096 -t rsa -f $PWD/ssh-keys/$KEY_NAME -q -N ""
    if [ $? -ne 0 ]
    then
        echo "Failed to generate ssh keys."
        exit 1
    else
        echo "New SSH keys created in directory : $PWD/ssh-keys"
        echo "/!\ DO NOT PUSH PRIVATE KEY IN GITHUB /!\."
    fi
    exit
fi

#Template & environment path
TEMPLATE_PATH=$PWD/TEMPLATE
ENV_PATH=$PWD/ENVIRONMENTS/$1

#Work directory name
if [[ "$2" == "dr" ]]; then
    WORK_DIRECTORY=$1"_dr_"$STACK_NAME"_"$STACK_FUNCTION
else
    WORK_DIRECTORY=$1"_"$STACK_NAME"_"$STACK_FUNCTION
fi
#Current directory path
CURRENT_DIRECTORY=$(pwd)

###
# Check template & environment existence
###
if [ ! -d $TEMPLATE_PATH ] || [ ! -d $ENV_PATH ];then 
	echo "Error. One the following directories does not exist :"
	echo "$TEMPLATE_PATH"
	echo "$ENV_PATH"
	exit 1
fi

###
# Get global-items directory path
###
GLOBAL_FOLDER_NAME="global-items"
while [[ $PWD != / ]] ; do
	GLOBAL_FOLDER_PATH=$(find "$PWD"/ -maxdepth 1 -type d -name "$GLOBAL_FOLDER_NAME")
	if [[ $GLOBAL_FOLDER_PATH ]]; then
		break
	fi 
	cd ..
done

if [[ -z $GLOBAL_FOLDER_PATH ]];then 
	echo "Error. $GLOBAL_FOLDER_NAME directory can not be found in GIT repository."
	exit
fi

###
# Create or update work directory
###
cd $CURRENT_DIRECTORY
if [ -d "./$WORK_DIRECTORY" ]; then
    echo "directory $CURRENT_DIRECTORY/$WORK_DIRECTORY already exist, updating."
    cd ./$WORK_DIRECTORY
    find ./ -type l -delete
else
    mkdir ./$WORK_DIRECTORY
    echo "$WORK_DIRECTORY created."
    cd ./$WORK_DIRECTORY
fi

###
# Symlink template & environment & global-items <=> workdirectory
###
for f in $(ls -d $TEMPLATE_PATH/*); do ln -sf $f ./; done
for f in $(ls -d $ENV_PATH/*); do ln -sf $f ./; done
for f in $(ls -d $GLOBAL_FOLDER_PATH/*); do ln -sf $f ./; done

###
# Adapt work directory and variables for DR
###
if [[ "$2" == "dr" ]]; then
    if [[ -L terragrunt.hcl ]]; then
        echo "DR init : Overwrite terragrunt.hcl"
        unlink terragrunt.hcl
        cp $ENV_PATH/terragrunt.hcl ./
        sed -i "s/$MAIN_REGION/$DR_REGION/g" terragrunt.hcl
        sed -i "s/$MAIN_STATE_BUCKET/$DR_STATE_BUCKET/g" terragrunt.hcl
        sed -i '$ s/.$//' terragrunt.hcl
        echo "  #Variables added for DR by init script" >> terragrunt.hcl
        echo "  aws-region=\"$DR_REGION\"" >> terragrunt.hcl
        echo "  suffix=\"$SUFFIX_DR\"" >> terragrunt.hcl
        echo "}" >> terragrunt.hcl
    fi
fi

###
# Get S3 modules
###
if test -f "../modules"; then
    echo "File 'modules' detected. Download modules from $RESOURCES_BUCKET."
    cat ../modules | while read -r module
    do
        if [ -d "./${module::-4}" ]; then
            echo "Module $module already present in $1 directory."
        else
            echo "Download $module in $1 directory."
            aws s3 cp s3://$RESOURCES_BUCKET/terraform/ed-modules/$module ./ --profile $PROFILE > get-module-${object::-4}.log
            unzip -o $module >> get-module-${module::-4}.log
            rm $module
        fi 
    done
fi