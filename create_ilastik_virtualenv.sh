#!/bin/bash

# Prerequisites
# Ubuntu: python-virtualenv mercurial
#    lemon: libglpk-dev coinor-libcbc-dev coinor-libclp-dev coinor-libcgl-dev libbz2-dev
#    cylemon: cython
#    pgmlink: libann-dev libboost-serialization-dev
#    qimage2ndarray: python-sip-dev qt4-dev-tools python-qt4-dev

# the location for the install
# the repositories will be checked out under this directory, there will also be
# a new virtualenv in $VIRTUALENVDIR
ROOT=$HOME/t
VIRTUALENVDIR=${ROOT}/ve

PATCH_BASE=$HOME
# options to pass to make, to have parallel builds use -j<num_cpus+1>
MAKEOPTS="-j13"

# where is cplex?
CPLEXBASE=




# where to get the sources?
HGURL_LEMON=http://lemon.cs.elte.hu/hg/lemon-main
GITURL_QIMAGE2NDARRAY=git://github.com/hmeine/qimage2ndarray.git
GITURL_VIGRA=git://github.com/ukoethe/vigra.git
GITURL_OPENGM=git://github.com/opengm/opengm.git

ILASTIK_GITHUB=git://github.com/ilastik
GITURL_ILASTIK=$ILASTIK_GITHUB/ilastik.git
GITURL_VOLUMINA=$ILASTIK_GITHUB/volumina.git
GITURL_LAZYFLOW=$ILASTIK_GITHUB/lazyflow.git
GITURL_PGMLINK=$ILASTIK_GITHUB/pgmlink.git
GITURL_CYLEMON=$ILASTIK_GITHUB/cylemon.git

# CPLEXBASE must be provided by editing this file
# exit early if it is not defined or the directory does not exit
if [[ -z "$CPLEXBASE" ]]; then
    echo "Please define CPLEX location by modifying the line with CPLEXBASE"
    exit 1
fi
if [[ ! -d "$CPLEXBASE" ]]; then
    echo "CPLEX directory does not exist. Exiting..."
    exit 1
fi


# build options 
COMMON_BUILD_OPTIONS="-DCMAKE_INSTALL_PREFIX=${VIRTUALENVDIR}"

LEMON_BUILDOPTIONS="-DILOG_CPLEX_LIBRARY=${CPLEXBASE}/cplex/lib/x86-64_sles10_4.1/static_pic/libcplex.a \
    -DILOG_CPLEX_INCLUDE_DIR=${CPLEXBASE}/cplex/include/ \
    -DILOG_CONCERT_INCLUDE_DIR=${CPLEXBASE}/concert/include/ \
    -DILOG_CONCERT_LIBRARY=${CPLEXBASE}/concert/lib/x86-64_sles10_4.1/static_pic/libconcert.a \
    -DBUILD_SHARED_LIBS=1"

# patches are declared as an array
LEMON_PATCHES=(lemon-1.3-as-needed.patch)

VIGRA_BUILDOPTIONS="-DVIGRANUMPY_INSTALL_DIR=${VIRTUALENVDIR}/lib/python2.7/site-packages \
    -DWITH_LEMON=1"
	# .. -DCMAKE_BUILD_TYPE=Debug

OPENGM_BUILDOPTIONS="-DBUILD_PYTHON_WRAPPER=1 -DWITH_BOOST=1 -DWITH_HDF5=1 \
    -DWITH_CPLEX=1 -DCPLEX_ROOT_DIR=${CPLEXBASE} \
    -DOPENGM_PYTHON_MODULE_INSTALL_DIR=${VIRTUALENVDIR}/lib/python2.7/site-packages"

PGMLINK_BUILDOPTIONS="-DCPLEX_ROOT_DIR=${CPLEXBASE} \
    -DVIGRA_INCLUDE_DIR=${VIRTUALENVDIR}/include/ \
    -DVIGRA_NUMPY_CORE_LIBRARY=${VIRTUALENVDIR}/lib/python2.7/site-packages/vigra/vigranumpycore.so"

set -e
export LC_ALL=POSIX
export LANG=en_US

[[ -d $ROOT ]] || mkdir -p $ROOT
cd $ROOT

function setup_virtualenv {
    pushd ${ROOT}
    virtualenv --system-site-packages ${VIRTUALENVDIR}

    # add CPATH, LIBRARY_PATH, and LD_LIBRARY_PATH to virtualenv's activate script
    cd ${VIRTUALENVDIR}/bin
    echo "export CPATH=${VIRTUALENVDIR}/include" >> activate
    echo "export LIBRARY_PATH=${VIRTUALENVDIR}/lib" >> activate
    echo "export LD_LIBRARY_PATH=$ROOT/ve/lib" >> activate

    popd
}

function clone_repos_base {
    CLONECMD=$1
    PKGNAME=$2
    URL=$3

    echo "Cloning ${PKGNAME}"
    $CLONECMD clone ${URL}
    DIRNAME=`basename ${URL}`
    # strip .git
    DIRNAME=${DIRNAME%.git}
    pushd $DIRNAME
    apply_patches ${PKGNAME}
    popd
}


function clone_repos {
    pushd ${ROOT}

    # clone various git repositories
    for i in ${!GITURL_*}; do
        PKGNAME=${i#GITURL_}
        clone_repos_base git $PKGNAME ${!i}
    done
    
    for i in ${!HGURL_*}; do
        PKGNAME=${i#HGURL_}
        clone_repos_base hg $PKGNAME ${!i}
    done

    popd
}

function apply_patches {
    PATCH_VNAME=${1}_PATCHES[@]
    for PATCHFILE in ${!PATCH_VNAME}; do
        echo "Trying patch: $PATCHFILE"
        FULLNAME=${PATCH_BASE}/${PATCHFILE}
        if [[ -f $FULLNAME ]]; then
            echo "Applying patch ${FULLNAME}"
            patch -p1 < ${FULLNAME}
        fi
    done
}

function build_cmake {
    # build the packages
    BUILDDIR=${ROOT}/build
    mkdir -p ${BUILDDIR}
    
    for i in {lemon-main,vigra,opengm,pgmlink}; do
    #for i in {pgmlink,}; do
        echo "Building ${i}..."
        CSOURCEDIR=${ROOT}/$i
        # filter postfix after dash "-"
        # variable names cannot have a dash, this is needed as a base to *_BUILDOPTIONS variable
        inodash=${i/-*} 
        CBUILDDIR=${BUILDDIR}/${inodash}
        mkdir -p ${CBUILDDIR}
        cd ${CBUILDDIR}
        OPTION_VAR_NAME=${inodash^^}_BUILDOPTIONS
        echo "${OPTION_VAR_NAME}: ${!OPTION_VAR_NAME}"
        cmake ${COMMON_BUILD_OPTIONS} ${!OPTION_VAR_NAME} ${CSOURCEDIR}
        make ${MAKEOPTS}
        make install
    done
}

function build_python {
    pushd ${ROOT}
    for i in {cylemon,qimage2ndarray}; do
        echo "Building ${i}..."
        cd ${i}
        python setup.py install
        cd ..
    done

    for i in {scikit-learn,futures,yapsy,faulthandler}; do
        pip install $i
    done
    
    popd
}

function setup_devel {
    pushd ${ROOT}
    for i in {lazyflow,volumina}; do
        echo "Setting up devel for $i"
        cd $i
        python setup.py develop
        cd ..
    done

    #build drtile
    cd lazyflow/lazyflow/drtile
    cmake .
    make

    popd
}

function write_scripts {
    pushd ${ROOT}
    cat > run_ilastik.sh <<EOL
#!/bin/bash

set -e

. ${VIRTUALENVDIR}/bin/activate
python ${ROOT}/ilastik/ilastik.py
EOL
    chmod +x run_ilastik.sh

    cat > update.sh <<EOL
#!/bin/bash

# exit on error
set -e

BASEDIR=${ROOT}


for i in {vigra,volumina,lazyflow,ilastik,pgmlink,cylemon,qimage2ndarray};
do
	echo Getting latest \$i changes...
	cd "\${BASEDIR}/\${i}";
	git pull;
done

. ${VIRTUALENVDIR}/bin/activate

for i in {vigra,opengm,pgmlink}; do
	echo "Building \$i..."
	cd "\${BASEDIR}/build/\$i";
	make install
done

for i in {cylemon,qimage2ndarray}; do
	echo "Building \$i..."
	cd "\${BASEDIR}/\$i";
	python setup.py install
done
EOL
    chmod +x update.sh

}
    

setup_virtualenv

clone_repos

# load environment from virtualenv
. ${VIRTUALENVDIR}/bin/activate

build_cmake

build_python

setup_devel

write_scripts
