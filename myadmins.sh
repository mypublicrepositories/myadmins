#!/bin/bash --

shopt -s -o nounset

declare -rx SCRIPT=${0##*/}

declare USER_PREFIX=""
declare ROLE_PREFIX=""
declare INTERFACE_PREFIX=""

declare SU=""
declare SUDO=""
declare GUI=""

umask 077

for util in /bin/grep /bin/awk /bin/sort /bin/cat /bin/bash /bin/chmod /bin/rm \
    /usr/bin/seinfo /bin/cp /bin/chmod /bin/head /bin/sed;
do
    if [ ! -x $util ] ; then
        printf "$SCRIPT:$LINENO: %s\n" "Utility '$util' is not executable" >&2
        exit 192
    fi
done

for util in /usr/sbin/semanage /usr/sbin/semodule /usr/sbin/useradd  \
    /usr/sbin/userdel /bin/whoami;
do
    if [ ! -f $util ] ; then
        printf "$SCRIPT:$LINENO: %s\n" "Utility '$util' is not available" >&2
        exit 192
    fi
done

if [ ! -c /dev/null ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Device '/dev/null' not found" >&2
    exit 192
fi

if [ ! -w $PWD ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Current directory '$PWD' is not writable" \
        >&2
    exit 192
fi

interface_prefixes() {
    if [ ! -d /usr/share/selinux/devel/include/ ] ; then
        printf "$SCRIPT:$LINENO: %s\n" "Directory \
'/usr/share/selinux/devel/include' not found" >&2
        exit 192
    fi

    /bin/grep -r "_admin',\`" /usr/share/selinux/devel/include/ | \
        /bin/awk -F "/" '{ print $8 }' | \
        /bin/awk -F "\`" '{ print $2 }' | \
        /bin/awk -F "_" '{ print $1 }' | /bin/sort
}

# Expects a single parameter: user_prefix

user() {
        /bin/cat > $1.te << EOF
policy_module($1, 1.0.0)

userdom_restricted_user_template($1)

EOF
}       

# Expects a single parameter: user_prefix

gui_user() {
        /bin/cat > $1.te << EOF
policy_module($1, 1.0.0)

userdom_unpriv_user_template($1)

EOF
}       

# Expects a single parameter: user_prefix

sudo() {
        /bin/cat >> $1.te <<EOF
optional_policy(\`
sudo_role_template($1, ${1}_r, ${1}_t)
')

EOF
}

# Expects single parameter: user_prefix

su() {
        /bin/cat >> $1.te <<EOF
optional_policy(\`
su_role_template($1, ${1}_r, ${1}_t)
')

optional_policy(\`
seutil_run_newrole(${1}_t, ${1}_r)
')

EOF
}

# Expects two parameters: user_prefix, role_prefix

role() {
        /bin/cat >> $1.te << EOF
userdom_base_user_template($2)

allow ${1}_r ${2}_r;    

EOF
}

# Expects two parameters: user_prefix, role_prefix

interface() {
        /bin/cat >> $1.te << EOF
optional_policy(\`
${interface}_admin(${2}_t, ${2}_r)
')

EOF
}

if [ $# -eq 0 ] ; then
        printf "%s\n" "Type --help for help."
        exit 192
fi

while [ $# -gt 0 ] ; do
    case "$1" in
        -h | --help)
            printf "%s\n" "$SCRIPT - Generate SELinux confined administrators"
            printf "%s\n" ""
            printf "%s\n" "-h | --help                                 Display this help message"
            printf "%s\n" "-l | --list                                 List service interface prefixes"
            printf "%s\n" "-r | --role [role_prefix]                   Role prefix"
            printf "%s\n" "-u | --user [user_prefix]                   User prefix"
            printf "%s\n" "-i | --interface [interface_prefix,(...)]   Service interface prefix"
            printf "%s\n" ""
            printf "%s\n" "--su                                        Enable SU for user"
            printf "%s\n" "--sudo                                      Enable SUDO for user"
            printf "%s\n" "--gui                                       User GUI support"
            printf "%s\n" ""
            printf "%s\n" "Examples:"
            printf "%s\n" ""
            printf "%s\n" "joe the apm administrator:"
            printf "%s\n" "$SCRIPT -u joe -r apmadm -i apm --sudo"
            printf "%s\n" ""
            printf "%s\n" "jane the lamp stack administrator:"
            printf "%s\n" "$SCRIPT -u jane -r lampadm -i apache,mysql,postfix --gui --su"
            exit 0
            ;;
        -l | --list )
 
            interface_prefixes
            exit 0
            ;;
        -r | --role ) shift

            if [ $# -eq 0 ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "Role prefix is missing" >&2
                exit 192
            fi

            if [ $(/usr/bin/seinfo -r"${1}_r" 2>/dev/null) ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "Role prefix '$1' is already taken" \
                    >&2
                exit 192
            fi

            if [ $(/usr/bin/seinfo -t"${1}_t" 2>/dev/null) ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "Role prefix '$1' is already taken" \
                    >&2
                exit 192
            fi

            ROLE_PREFIX="$1"
            ;;
        -u | --user )

            shift

            if [ $# -eq 0 ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "User prefix is missing" >&2
                exit 192
            fi

            if [ $(/usr/bin/seinfo -r"${1}_r" 2>/dev/null) ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "User prefix '$1' is already taken" \
                    >&2
                exit 192
            fi

            if [ $(/usr/bin/seinfo -t"${1}_t" 2>/dev/null) ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "User prefix '$1' is already taken" \
                    >&2
                exit 192
            fi

            if [ "$(/bin/grep "${1}" /etc/passwd | \
                awk -F ":" '{ print $1 }')" == "${1}" ] ; then  
                printf "$SCRIPT:$LINENO: %s\n" "User '$1' already exists" >&2
                exit 192
            fi

            USER_PREFIX="$1"
            ;;
        -i | --interface )

            shift

            if [ $# -eq 0 ] ; then
                printf "$SCRIPT:$LINENO: %s\n" "Interface prefix is missing" >&2
                exit 192
            fi

            INTERFACE_PREFIX="$1"
            ;;
        --su )

            SU=SU
            ;;
        --sudo )

            SUDO=SUDO
            ;;
        --gui )

            GUI=GUI
            ;;
        -* )

            printf "$SCRIPT:$LINENO: %s\n" "switch $1 not supported" >&2
            exit 192
            ;;
        * )

            printf "$SCRIPT:$LINENO: %s\n" "extra argument or missing switch" \
                >&2
            exit 192
            ;;
    esac
    shift
done

if [ -z "$ROLE_PREFIX" ] ; then
        printf "%s\n" "Role prefix missing" >&2
        exit 192
fi

if [ -z "$USER_PREFIX" ] ; then
        printf "%s\n" "User prefix missing" >&2
        exit 192
fi

if [ -z "$INTERFACE_PREFIX" ] ; then
        printf "$SCRIPT:$LINENO: %s\n" "Interface prefix missing" >&2
        exit 192
fi

if [ ! -f /usr/share/selinux/devel/include/system/userdomain.if ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "File '/usr/share/selinux/devel/include/system/userdomain.if' not found" \
        >&2
    exit 192
elif [ $(/bin/grep userdom_restricted_user_template \
/usr/share/selinux/devel/include/system/userdomain.if \
| /bin/awk -F "\`" '{ print $2 }' | /bin/awk -F "\'" '{ print $1 }' 2>/dev/null) \
    != "userdom_restricted_user_template" ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Template 'userdom_restricted_user_template()' not found" \
        >&2
    exit 192
elif [ $(/bin/grep userdom_unpriv_user_template \
    /usr/share/selinux/devel/include/system/userdomain.if \
    | /bin/awk -F "\`" '{ print $2 }' | /bin/awk -F "\'" '{ print $1 }' \
    2>/dev/null) != "userdom_unpriv_user_template" ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Template 'userdom_unpriv_user_template()' not found" \
        >&2
    exit 192
fi

if [ ! -f /usr/share/selinux/devel/include/admin/sudo.if ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "File '/usr/share/selinux/devel/include/admin/sudo.if' not found" \
        >&2
    exit 192
elif [ $(/bin/grep sudo_role_template /usr/share/selinux/devel/include/admin/sudo.if \
    | /bin/awk -F "\`" '{ print $2 }' | /bin/awk -F "\'" '{ print $1 }' 2>/dev/null) \
    != "sudo_role_template" ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Template 'sudo_role_template()' not found" \
        >&2
    exit 192
fi

if [ ! -f /usr/share/selinux/devel/include/admin/su.if ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "File '/usr/share/selinux/devel/include/admin/su.if' not found" \
        >&2
    exit 192
elif [ $(/bin/grep su_role_template /usr/share/selinux/devel/include/admin/su.if \
    | /bin/awk -F "\`" '{ print $2 }' | /bin/awk -F "\'" '{ print $1 }' \
    2>/dev/null) != "su_role_template" ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Template 'su_role_template()' not found" >&2
    exit 192
fi

if [ ! -f /usr/share/selinux/devel/include/system/selinuxutil.if ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "File '/usr/share/selinux/devel/include/system/selinuxutil.if' not found" \
        >&2
    exit 192
elif [ $(/bin/grep seutil_run_newrole \
    /usr/share/selinux/devel/include/system/selinuxutil.if \
    | /bin/awk -F "\`" '{ print $2 }' | /bin/awk -F "\'" '{ print $1 }' \
    2>/dev/null) != "seutil_run_newrole" ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Interface 'seutil_run_newrole()' not found" \
        >&2
    exit 192
fi

if [ ! -f /usr/share/selinux/devel/include/support/misc_macros.spt ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "File '/usr/share/selinux/devel/include/support/misc_macros.spt' not found" \
        >&2
    exit 192
elif [ $(/bin/grep gen_user \
    /usr/share/selinux/devel/include/support/misc_macros.spt \
    | /bin/awk -F "\`" '{ print $2 }' | /bin/awk -F "\'" '{ print $1 }' \
    2>/dev/null) != "gen_user" ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Interface 'gen_user()' not found" >&2
    exit 192
fi

if [ ! $(/usr/bin/seinfo -rsystem_r 2>/dev/null) ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Role 'system_r' not found" >&2
    exit 192
fi

if [ ! $(/usr/bin/seinfo -tlocal_login_t 2>/dev/null) ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Type 'local_login_t' not found" >&2
    exit 192
fi

if [ ! $(/usr/bin/seinfo -tsshd_t 2>/dev/null) ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Type 'sshd_t' not found" >&2
    exit 192
fi

if [ ! $(/usr/bin/seinfo -txdm_t 2>/dev/null) ] ; then
    printf "$SCRIPT:$LINENO: %s\n" "Type 'xdm_t' not found" >&2
    exit 192
fi

if [ -f "${USER_PREFIX}.te" ] ; then
    printf "%s\n" "Replacing '${USER_PREFIX}.te' source policy file" >&2
fi

if [ ! -z "$USER_PREFIX" -a "$GUI" == "GUI" ] ; then
        gui_user $USER_PREFIX
elif [ ! -z "$USER_PREFIX" -a "$GUI" == "" ] ; then
        user $USER_PREFIX
else
        printf "$SCRIPT:$LINENO: %s\n" "Unhandled exception" >&2
        exit 192;
fi

if [ "$SUDO" == "SUDO" ] ; then
        sudo $USER_PREFIX
fi

if [ "$SU" == "SU" ] ; then
        su $USER_PREFIX
fi

if [ ! -z "$ROLE_PREFIX" ] ; then
        role $USER_PREFIX $ROLE_PREFIX
fi

if [ ! -z "$INTERFACE_PREFIX" ] ; then

        INTERFACE_PREFIX=$(printf "%s\n" "$INTERFACE_PREFIX" | /bin/sed s/,/" "/g)

        for interface in $INTERFACE_PREFIX; do
                interface_prefixes | /bin/grep $interface >/dev/null

                if [ "$?" != 0 ] ; then
                        printf "$SCRIPT:$LINENO: %s\n" "Interface prefix '$interface' unavailable" \
                            >&2
                        /bin/rm -f $USER_PREFIX.te
                        exit 192
                fi
        done
fi

for interface in $INTERFACE_PREFIX; do
    interface $USER_PREFIX $ROLE_PREFIX
done

/bin/cat >> ${USER_PREFIX}.te <<EOF
gen_user(${USER_PREFIX}_u, user, ${USER_PREFIX}_r ${ROLE_PREFIX}_r, s0, s0 - mls_systemhigh, mcs_allcats)

EOF

if [ ! -z "$USER_PREFIX" -a "$GUI" == "GUI" ] ; then
    if [ "$(/usr/bin/seinfo --sensitivity | /bin/head -n 1 | /bin/awk -F " " \
'{ print $2 }')" == "0" ] ; then
        /bin/cat > ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_t ${USER_PREFIX}_r:${USER_PREFIX}_t
system_r:local_login_t ${USER_PREFIX}_r:${USER_PREFIX}_t
system_r:sshd_t ${USER_PREFIX}_r:${USER_PREFIX}_t
system_r:xdm_t ${USER_PREFIX}_r:${USER_PREFIX}_t
EOF
    else
        /bin/cat > ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
system_r:local_login_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
system_r:sshd_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
system_r:xdm_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
EOF
    fi
elif [ ! -z "$USER_PREFIX" -a "$GUI" == "" ] ; then
    if [ "$(/usr/bin/seinfo --sensitivity | /bin/head -n 1 | /bin/awk -F " " \
'{ print $2 }')" == "0" ] ; then
        /bin/cat > ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_t ${USER_PREFIX}_r:${USER_PREFIX}_t
system_r:local_login_t ${USER_PREFIX}_r:${USER_PREFIX}_t
system_r:sshd_t ${USER_PREFIX}_r:${USER_PREFIX}_t
EOF
    else
    /bin/cat > ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
system_r:local_login_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
system_r:sshd_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
EOF
    fi
else
        printf "$SCRIPT:$LINENO: %s\n" "Unhandled exception" >&2
        exit 192;
fi

if [ "$SUDO" == "SUDO" ] ; then
    if [ "$(/usr/bin/seinfo --sensitivity | /bin/head -n 1 | /bin/awk -F " " \
'{ print $2 }')" == "0" ] ; then
        /bin/cat >> ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_sudo_t ${USER_PREFIX}_r:${USER_PREFIX}_t
EOF
    else
        /bin/cat >> ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_sudo_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
EOF
    fi
fi

if [ "$SU" == "SU" ] ; then
    if [ "$(/usr/bin/seinfo --sensitivity | /bin/head -n 1 | /bin/awk -F " " \
'{ print $2 }')" == "0" ] ; then
    /bin/cat >> ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_su_t ${USER_PREFIX}_r:${USER_PREFIX}_t
EOF
    else
    /bin/cat >> ${USER_PREFIX}_u <<EOF
${USER_PREFIX}_r:${USER_PREFIX}_su_t:s0 ${USER_PREFIX}_r:${USER_PREFIX}_t:s0
EOF
    fi
fi

if [ -f "${USER_PREFIX}_setup.sh" ] ; then
    printf "%s\n" "Replacing '${USER_PREFIX}_setup.sh' script" >&2
fi

/bin/cat > ${USER_PREFIX}_setup.sh <<EOF
#!/bin/bash --

shopt -s -o nounset

declare -rx SCRIPT=\${0##*/}

for util in /usr/sbin/semanage /usr/sbin/semodule /usr/sbin/useradd  \
/bin/bash /bin/grep /bin/cp /bin/chmod /bin/awk /bin/head;
do
if [ ! -x \$util ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Utility '\$util' is not executable" >&2
exit 192
fi
done

if [ ! -r /etc/selinux/config ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/selinux/config' not readable" >&2
exit 192
fi

if [ ! -f /usr/share/selinux/devel/Makefile ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/usr/share/selinux/devel/Makefile' not found" \
>&2
exit 192
fi

if [ "\$(/usr/sbin/semodule -l | /bin/grep "$USER_PREFIX" | \
awk -F " " '{ print \$1 }')" == "${USER_PREFIX}" ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Module with name '$USER_PREFIX' already exists" \
>&2
exit 192
fi

if [ "\$(/usr/sbin/semodule -l | /bin/grep "${USER_PREFIX}" | \
/bin/awk -F " " '{ print \$1 }' | /bin/grep ^$USER_PREFIX$ )" == "$USER_PREFIX" ] ; \
then
printf "\$SCRIPT:\$LINENO: %s\n" "Module with name '$USER_PREFIX' already exists" \
>&2
exit 192
fi

if [ ! -d /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/selinux/"\$(/bin/grep \
^SELINUXTYPE= /etc/selinux/config | /bin/awk -F "=" '{ print \$2 }' | \
/bin/awk -F " " '{ print \$1 }')"/contexts/users/' not found" >&2
exit 192
elif [ ! -w /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/selinux/"\$(/bin/grep \
^SELINUXTYPE= /etc/selinux/config | /bin/awk -F "=" '{ print \$2 }' | \
/bin/awk -F " " '{ print \$1 }')"/contexts/users/' is not writable" >&2
exit 192
fi

if [ -f /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/${USER_PREFIX}_u ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File \
'/etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/${USER_PREFIX}_u' already exists" >&2
exit 192
fi

if [ ! -r /etc/passwd ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/passwd' not readable" >&2
exit 192
fi

if [ "\$(/bin/grep "${USER_PREFIX}" /etc/passwd | \
awk -F ":" '{ print \$1 }' | /bin/grep ^$USER_PREFIX$ )" == \
"${USER_PREFIX}" ] ; then  
printf "\$SCRIPT:\$LINENO: %s\n" "User '${USER_PREFIX}' already exists" >&2
exit 192
fi

if [ "\$(/usr/sbin/semanage login -l | /bin/grep "${USER_PREFIX}" | \
/bin/awk -F " " '{ print \$1 }' | /bin/grep ^$USER_PREFIX$ )" == "$USER_PREFIX" ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "User '${USER_PREFIX}' is already associated" \
>&2
exit 192
elif [ "\$(/usr/sbin/semanage login -l | /bin/grep "${USER_PREFIX}" | \
/bin/awk -F " " '{ print \$2 }' | /bin/grep ^$USER_PREFIX$ )" == \
"${USER_PREFIX}_u" ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Identity '${USER_PREFIX}_u' already exists" \
>&2
exit 192
fi

if [ ! -f /etc/security/sepermit.conf ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/security/sepermit.conf' not found" \
>&2
exit 192
elif [ ! -w /etc/security/sepermit.conf ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "User '/etc/security/sepermit.conf' is not writable" \
>&2
exit 192
fi

printf "%s\n" "Compiling '${USER_PREFIX}.pp' from '${USER_PREFIX}.te'"
make -f /usr/share/selinux/devel/Makefile ${USER_PREFIX}.pp

printf "%s\n" "Installing '${USER_PREFIX}.pp'"
/usr/sbin/semodule -i ${USER_PREFIX}.pp

printf "%s\n" "Copying '${USER_PREFIX}_u' to '/etc/selinux/"\$(/bin/grep \
^SELINUXTYPE= /etc/selinux/config | /bin/awk -F "=" '{ print \$2 }' | \
/bin/awk -F " " '{ print \$1 }')"/contexts/users/'"
/bin/cp ${USER_PREFIX}_u /etc/selinux/"\$(/bin/grep \
^SELINUXTYPE= /etc/selinux/config | /bin/awk -F "=" '{ print \$2 }' | \
/bin/awk -F " " '{ print \$1 }')"/contexts/users/

printf "%s\n" "Adding a new user called '$USER_PREFIX'"
/usr/sbin/useradd $USER_PREFIX

printf "%s\n" "Do not forget to set a password for user '$USER_PREFIX' manually!"

printf "%s\n" "Associating '$USER_PREFIX' with '${USER_PREFIX}_u'"

if [ "\$(/usr/bin/seinfo --sensitivity | /bin/head -n 1 | /bin/awk -F " " \
'{ print \$2 }')" == "0" ] ; then
/usr/sbin/semanage login -a -s ${USER_PREFIX}_u $USER_PREFIX
else
/usr/sbin/semanage login -a -s ${USER_PREFIX}_u -r s0 $USER_PREFIX
fi

printf "%s\n" "Appending '$USER_PREFIX' to '/etc/security/sepermit.conf'"
printf "%s\n" "$USER_PREFIX" >> /etc/security/sepermit.conf

EOF

if [ "$SUDO" == "SUDO" ] ; then
    /bin/cat >> ${USER_PREFIX}_setup.sh <<EOF
if [ ! -d /etc/sudoers.d/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/sudoers.d' not found" >&2
exit 192
elif [ ! -w /etc/sudoers.d/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/sudoers.d' is not writable" \
>&2
exit 192
elif [ -f /etc/sudoers.d/${USER_PREFIX} ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/sudoers.d/${USER_PREFIX}' already exists" \
>&2
exit 192
fi

printf "%s\n" "Setting up sudo for '$USER_PREFIX'"
printf "%s\n" "$USER_PREFIX \${HOSTNAME}=(root) ALL" > \
/etc/sudoers.d/$USER_PREFIX
/bin/chmod 0440 /etc/sudoers.d/$USER_PREFIX

#EOF
EOF
fi

/bin/chmod +x ${USER_PREFIX}_setup.sh 

if [ -f "${USER_PREFIX}_remove.sh" ] ; then
    printf "%s\n" "Replacing '${USER_PREFIX}_remove.sh' script" >&2
fi

/bin/cat > ${USER_PREFIX}_remove.sh <<EOF
#!/bin/bash --

shopt -s -o nounset

declare -rx SCRIPT=\${0##*/}

for util in /usr/sbin/semanage /usr/sbin/semodule /usr/sbin/userdel \
/bin/rm /bin/bash /bin/grep /bin/awk /bin/sed;
do
if [ ! -x $util ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Utility '$util' is not executable" >&2
exit 192
fi
done

if [ "\$(/usr/sbin/semanage login -l | /bin/grep "${USER_PREFIX}" | \
/bin/awk -F " " '{ print \$1 ":" \$2}' | /bin/grep ^${USER_PREFIX}:${USER_PREFIX}_u$ )" != \
""$USER_PREFIX":"${USER_PREFIX}_u"" ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Association '"${USER_PREFIX}":"${USER_PREFIX}_u"' not found" \
>&2
exit 192
fi

if [ "\$(/bin/cat /etc/passwd | /bin/awk -F ":" '{ print \$1 }' | /bin/grep ^ed$ )" \
!= "${USER_PREFIX}" ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "User '${USER_PREFIX}' does not exist" >&2
exit 192
fi

if [ "\$(/usr/sbin/semodule -l | /bin/grep "${USER_PREFIX}" | \
/bin/awk -F " " '{ print \$1 }' | /bin/grep ^$USER_PREFIX$ )" != \
"$USER_PREFIX" ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Module with name '$USER_PREFIX' is not installed" \
>&2
exit 192
fi

if [ ! -d /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/selinux/"\$(/bin/grep \
^SELINUXTYPE= /etc/selinux/config | /bin/awk -F "=" \
'{ print \$2 }' | /bin/awk -F " " '{ print \$1 }')"/contexts/users/' not found" \
>&2
exit 192
elif [ ! -w /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/selinux/"\$(/bin/grep \
^SELINUXTYPE= /etc/selinux/config | /bin/awk -F "=" \
'{ print \$2 }' | /bin/awk -F " " '{ print \$1 }')"/contexts/users/' is not writable" \
>&2
exit 192
fi

if [ ! -f /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/${USER_PREFIX}_u ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config |/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " '{ print \$1 }')"/contexts/users/${USER_PREFIX}_u' does not exist" \
>&2
exit 192
fi

if [ ! -f /etc/security/sepermit.conf ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/security/sepermit.conf' not found" \
>&2
exit 192
elif [ ! -w /etc/security/sepermit.conf ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "User '/etc/security/sepermit.conf' is not writable" \
>&2
exit 192
fi

printf "%s\n" "Removing association of '$USER_PREFIX' with '${USER_PREFIX}_u'"

if [ "\$(/usr/bin/seinfo --sensitivity | /bin/head -n 1 | /bin/awk -F " " \
'{ print \$2 }')" \
== "0" ] ; then
/usr/sbin/semanage login -d -s ${USER_PREFIX}_u $USER_PREFIX
else
/usr/sbin/semanage login -d -s ${USER_PREFIX}_u -r s0 $USER_PREFIX
fi

printf "%s\n" "Removing a user called '$USER_PREFIX'"
/usr/sbin/userdel -r $USER_PREFIX

printf "%s\n" "Uninstalling the '$USER_PREFIX' module"
/usr/sbin/semodule -r $USER_PREFIX

printf "%s\n" "Removing '/etc/selinux/"\$(/bin/grep ^SELINUXTYPE= \
/etc/selinux/config | /bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/${USER_PREFIX}_u'"
/bin/rm -f /etc/selinux/"\$(/bin/grep ^SELINUXTYPE= /etc/selinux/config | \
/bin/awk -F "=" '{ print \$2 }' | /bin/awk -F " " \
'{ print \$1 }')"/contexts/users/${USER_PREFIX}_u


printf "%s\n" "Removing '${USER_PREFIX}' from '/etc/security/sepermit.conf'"
 
if [ "\$(/bin/grep ^"$USER_PREFIX" /etc/security/sepermit.conf)" == \
"$USER_PREFIX" ] ; then
/bin/sed -i "/^${USER_PREFIX}$/d" /etc/security/sepermit.conf
fi

EOF

if [ "$SUDO" == "SUDO" ] ; then
    /bin/cat >> ${USER_PREFIX}_remove.sh <<EOF
if [ ! -d /etc/sudoers.d/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/sudoers.d' not found" >&2
exit 192
elif [ ! -w /etc/sudoers.d/ ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "Directory '/etc/sudoers.d' is not writable" \
>&2
exit 192
elif [ ! -f /etc/sudoers.d/${USER_PREFIX} ] ; then
printf "\$SCRIPT:\$LINENO: %s\n" "File '/etc/sudoers.d/${USER_PREFIX}' does not exist" \
>&2
exit 192
fi

printf "%s\n" "Removing '/etc/sudoers.d/$USER_PREFIX'"
/bin/rm -f /etc/sudoers.d/$USER_PREFIX

#EOF
EOF
fi

/bin/chmod +x ${USER_PREFIX}_remove.sh

#EOF
