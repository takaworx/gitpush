#!/bin/bash

# source: https://gist.github.com/francoisromain/58cabf43c2977e48ef0804848dee46c3
# and another script to delete the directories created by this script
# project-delete.sh: https://gist.github.com/francoisromain/e28069c18ebe8f3244f8e4bf2af6b2cb

# Call this file with `bash ./project-create.sh project-name [service-name]`
# - project-name is mandatory
# - service-name is optional

# This will creates 4 directories and a git `post-receive` hook.
# The 4 directories are:
# - $GIT: a git repo
# - $TMP: a temporary directory for deployment
# - $WWW: a directory for the actual production files
# - $ENV: a directory for the env variables

# When you push your code to the git repo,
# the `post-receive` hook will deploy the code
# in the $TMP directory, then copy it to $WWW.

function dir_create() {
	sudo mkdir -p "$1"
	cd "$1" || exit

	# Define group recursively to "users", on the directories
	sudo chgrp -R users .

	# Define permissions recursively, on the sub-directories
	# g = group, + add rights, r = read, w = write, X = directories only
	# . = curent directory as a reference
	sudo chmod -R g+rwX .
}

if [ $# -eq 0 ]; then
	echo 'No project name provided (mandatory)'
	exit 1
else
	echo "- Project name:" "$1"
fi

echo "IMPORTANT: ADD THE TRAILING SLASH AT THE END OF YOUR DIRECTORIES!"
read -p "Deployment directory (e.g. /var/www/html/) : " DIR_WWW
DIR_WWW=${DIR_WWW:-/var/www/html/}
read -p "Temporary directory for deployment (e.g. /var/www/tmp/) : " DIR_TMP
DIR_TMP=${DIR_TMP:-/var/www/tmp/}
read -p "Git project directory (e.g. /var/www/git/) : " DIR_GIT
DIR_GIT=${DIR_GIT:-/var/www/git/}
read -p "Environment directory (e.g. /var/www/env/) : " DIR_ENV
DIR_ENV=${DIR_ENV:-/var/www/env/}
read -p "Git branch to hook (e.g. master) : " GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-master}

if [ -z "$2" ]; then
	echo '- Service name (optional): not provided'
	GIT=$DIR_GIT$1.git
	TMP=$DIR_TMP$1
	WWW=$DIR_WWW$1
	ENV=$DIR_ENV$1
else
	echo "- Service name (optional):" "$2"
	GIT=$DIR_GIT$1.$2.git
	TMP=$DIR_TMP$1.$2
	WWW=$DIR_WWW$1/$2
	ENV=$DIR_ENV$1/$2

	# Create $WWW parent directory
	dir_create "$DIR_WWW$1"
fi

echo "- git:" "$GIT"
echo "- tmp:" "$TMP"
echo "- www:" "$WWW"
echo "- env:" "$ENV"

export GIT
export TMP
export WWW
export ENV
export GIT_BRANCH

# Create a directory for the env repository
sudo mkdir -p "$ENV"
cd "$ENV" || exit
sudo touch .env

# Create a directory for the git repository
sudo mkdir -p "$GIT"
cd "$GIT" || exit

# Init the repo as an empty git repository
sudo git init --bare

# Define group recursively to "users", on the directories
sudo chgrp -R users .

# Define permissions recursively, on the sub-directories
# g = group, + add rights, r = read, w = write, X = directories only
# . = curent directory as a reference
sudo chmod -R g+rwX .

# Sets the setgid bit on all the directories
# https://www.gnu.org/software/coreutils/manual/html_node/Directory-Setuid-and-Setgid.html
sudo find . -type d -exec chmod g+s '{}' +

# Make the directory a shared repo
sudo git config core.sharedRepository group

cd hooks || exit

# create a post-receive file
sudo tee post-receive <<EOF
#!/bin/bash
while read oldrev newrev refname
do
	branch=\$(git rev-parse --symbolic --abbrev-ref $refname)
    if [ "$GIT_BRANCH" == "\$branch" ]; then
        
		# The production directory
		WWW="${WWW}"

		# A temporary directory for deployment
		TMP="${TMP}"

		# The Git repo
		GIT="${GIT}"

		# The Env  repo
		ENV="${ENV}"

		# Deploy the content to the temporary directory
		mkdir -p \$TMP
		git --work-tree=\$TMP --git-dir=\$GIT checkout -f

		# Copy the env variable to the temporary directory
		cp -a \$ENV/. \$TMP

		# Do stuffs, like npm install
		cd \$TMP || exit

		# Replace the content of the production directory
		# with the temporary directory
		cd / || exit
		rm -rf \$WWW
		mv \$TMP \$WWW

		# Do stuff like starting docker
		cd \$WWW || exit
		# docker-compose up -d --build

    fi
done

EOF

# make it executable
sudo chmod +x post-receive