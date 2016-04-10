#!/bin/bash

# GnuPG wrapper by Trepet
# © GPLv3

# Set if necessary
#export GNUPGHOME="$HOME/.gnupg"

# Explicit choice of dmenu or rofi for key selection
#menu='dmenu'
#menu='rofi'
#menu='zenity'

# Dialog options
zenity_size="--height=600 --width=800 "
zenity_ask_size="--height=510 --width=280 "
zenity_key_size_h="--height=500"
zenity_key_size_w="--width=400"
rofi_prompt="Search: "

# GPG cipher for symmetric encription
gpg_sym_cipher='--cipher-algo AES256'

# Debug
#export LANG=en-us

# Code       #
##############
PROGRAM="${0##*/}"

usage() {
  cat <<EOF

GnuPG wrapper by Trepet

usage: $PROGRAM [action]

  action:
    e - encrypt message
    ec - encrypt message symmetrically
    d - decrypt/verify message
    s - sign message
    se - sign & enrypt message
    ef - encrypt file
    efc - encrypt file symmetrically
    df - decrypt/verify file
    im - import key
    ex - export key
    gen - generate new key
    del - delete keys

  Examples:
    $PROGRAM d
    $PROGRAM e
    $PROGRAM df

  Config (check source)
    GPG home dir:
    $GNUPGHOME

  Using 4096 RSA with no expire date for
  key generation.

  Expired and revoked uids are ignored. Use
  --invalid parameter with del or ex action
  to list those.
EOF
}

if [[ $1 = @(-h|--help) ]]; then
  usage
  exit $(( $# ? 0 : 1 ))
fi

if [[ !($(command -v zenity)) ]]; then
  echo "zenity is needed to run this script"
  exit 1
fi

# Old zenity workaround
if [[ $(printf "3.18\n$(zenity --version)\n" | sort -V | head -1) != '3.18' ]]; then
  old_zenity=1
  g_tmp_dir="/dev/shm/g_tmp"
  tmpfile="$g_tmp_dir/.${RANDOM}"
  [[ -d "$g_tmp_dir" ]] || mkdir --mode=go-rwx "$g_tmp_dir" || exit 1
fi

if [[ -z $menu ]]; then
  menu='zenity'
  [[ ($(command -v dmenu)) ]] && menu='dmenu'
  [[ ($(command -v rofi)) ]] && menu='rofi'
fi

#if [[ -z $menu ]]; then
#  echo "dmenu or rofi is needed to run this script"
#  exit 1
#fi

die() {
	echo "$@" >&2
	exit 1
}

zenity_die () {
  #error_mesg=$(echo -e $@ | sed -e 's/\\/\\\\/g' -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')
  zenity --error --no-markup --text "$@"
	exit 1
}

rofi_cmd () {
  [[ $secret -eq 1 ]] && rofi_mesg='<b>Choose secret key to sign</b>' || rofi_mesg='<b>Choose key(s), Esc to finish</b>'
  rofi -dmenu -i -bg \#222222 -fg \#ffffff -hlbg \#222222 -hlfg \#11dd11 -opacity 90 -lines 20 -width -60 -font "mono 16" -no-levenshtein-sort -disable-history -p "$rofi_prompt" -mesg "$rofi_mesg"
}

dmenu_cmd () {
  dmenu -l 20 -b -nb \#222222 -nf \#ffffff -sb \#222222 -sf \#11dd11
}

zenity_cmd () {
  [[ $encrypt -eq 1 ]] && zen_list_param='--checklist' zen_sep='|-r ' title='--title=Public keys' text='--text=Check encryption keys'
  [[ $secret -eq 1 ]] && zen_list_param='--radiolist' zen_sep='|' title='--title=Secret keys' text='--text=Choose signing key'
  [[ $export -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Export keys' text='--text=Check keys to export'
  [[ $delete -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Delete key(s)' text='--text=Choose key(s) to delete'
  zenity "$zenity_key_size_h" "$zenity_key_size_w" "$text" "$title" "$zen_list_param" --list --hide-header --separator="$zen_sep" --column="Check" --column="Key"
}

list_uids () {
  [[ $secret -eq 1 ]] && gpg_list='-K' || gpg_list='-k'
  more_grep=( 'grep' '-vE' '^uid:e|^uid:r|^uid:n|^uid:i' )
  [[ $invalid -eq 1 ]] && more_grep=( 'grep' '-E' '^uid:e|^uid:r|^uid:n|^uid:i' )
  if [[ $menu == 'zenity' ]]; then
    gpg $gpg_list --with-colons --fixed-list-mode | grep uid: | "${more_grep[@]}" | cut -f10 -d ":" | sort -df | sed -e 's/\\x3a/:/' | sed -e 's/^/FALSE\n/'| zenity_cmd
  else
    gpg $gpg_list --with-colons --fixed-list-mode | grep uid: | "${more_grep[@]}" | cut -f10 -d ":" | sort -df | sed -e 's/\\x3a/:/' | ${menu}_cmd
  fi
}

import_key () {
  local oklabel='Import'
  local result=$(zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" | gpg --no-tty --import -v --logger-fd 1)
  zenity --info --no-markup --title="Importing result" --text="${result//gpg: }"
}

export_key () {
  local oklabel='Export'
  choose_uids
  if [[ ${#keys[@]} -ne 0 ]]; then
    gpg --export --armor "${keys[@]}" | zenity $zenity_size --text-info --title="$zenity_title" --ok-label="$oklabel"
  else
    exit 1
  fi
}

choose_uids () {
  if [[ $menu == 'zenity' ]]; then
    unset keys
    if [[ $encrypt -eq 1 ]] && [[ $secret -ne 1 ]]; then
      uid_output="-r $(list_uids)"
    elif [[ $secret -ne 1 ]]; then
      uid_output="$(list_uids)"
    fi && \
    #echo "$uid_output" && \ # debug
    local IFS='|' && \
    read -r -a keys <<< "$uid_output"
  else
    [[ $secret -ne 1 ]] && uid_output="$(list_uids)"
    if [[ $? -ne 1 ]]; then
      [[ $encrypt -eq 1 ]] && keys+=("-r $uid_output") || keys+=("$uid_output")
      #echo "${keys[@]}" # debug
      choose_uids
    fi
  fi

  if [[ $secret -eq 1 ]] && [[ -z $sign_key ]]; then
    sign_key="$(list_uids)"
  fi
}

edit_message () {
  [[ $decrypt -eq 1 ]] && local oklabel='Decrypt' || local oklabel='Encrypt'
  if [[ $old_zenity -eq 1 && -n $message ]]; then
    echo -e "$message" > "$tmpfile"
    zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" --filename="$tmpfile" 2>/dev/null && \
    rm "$tmpfile" || $(rm "$tmpfile" && false)
  else
    zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" 2>/dev/null
  fi
}

encrypt_message () {
  if [[ ${#keys[@]} -ne 0 ]]; then
    echo "${keys[@]}" # debug
    echo "$message" | gpg --armor --encrypt --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
    zenity $zenity_size --text-info --title="Encrypted for: $(echo -e ${keys[@]//-r})" 2>/dev/null || \
    (unset keys && encrypt_message)
  else
    if [[ -z "$message" ]]; then
      message=$(edit_message)
    else
      message=$(echo -e "$message" | edit_message)
    fi
    [[ $? -eq 1 ]] && exit 1
    choose_uids && \
    encrypt_message
  fi
}

encrypt_message_sym () {
  if [[ -z "$message" ]]; then
    message=$(edit_message)
  else
    message=$(echo -e "$message" | edit_message)
  fi
  [[ $? -eq 1 ]] && exit 1
  echo "$message" | gpg --armor --symmetric $gpg_sym_cipher --logger-fd 1 2>/dev/null | \
  zenity $zenity_size --text-info --title="Encrypted" 2>/dev/null || \
  encrypt_message_sym
}

decrypt_message () {
  encrypted_message="$(edit_message)" || exit 1
  message=$(echo "$encrypted_message" | gpg --decrypt --no-tty --logger-fd 1 2>/dev/null | sed '0,/^gpg: /s/^gpg: /\n\nGPG:\ngpg: /' | sed 's/^gpg: //')
  if [[ $old_zenity -eq 1 ]]; then
    echo -e "$message" > "$tmpfile"
    zenity $zenity_size --title="Decrypted text" --text-info --filename="$tmpfile" 2>/dev/null
    rm "$tmpfile"
  else
    echo -e "$message" | zenity $zenity_size --title="Decrypted text" --text-info 2>/dev/null
  fi & \
  if [[ $message == *'-----BEGIN PGP SIGNED MESSAGE-----'* ]]; then
    sig_check=$(echo -e "$message" | gpg --no-tty -v --verify --logger-fd 1 2>/dev/null)
    zenity --info --no-markup --title="Signature check" --text="${sig_check//gpg: }"
  fi
}

sign_message () {
  unset secret
  if [[ -n $sign_key ]]; then
    if [[ $encrypt -eq 1 ]]; then
      choose_uids || sign_message
      #echo "R: ${keys[@]}" # debug
      #echo "S: $sign_key" # debug
      echo -e "$message" | gpg -es --armor --no-tty --local-user "$sign_key" --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
      zenity $zenity_size --title="Signed by $(echo -e $sign_key) & encrypted for: $(echo -e ${keys[@]//-r})" --text-info 2>/dev/null
    else
      if [[ $old_zenity -eq 1 ]]; then
        echo -e "$message" | gpg --clearsign --armor --no-tty --local-user "$sign_key" --logger-fd 1 2>/dev/null > "$tmpfile"
        zenity $zenity_size --title="Signed by $(echo -e $sign_key)" --text-info --filename="$tmpfile" 2>/dev/null
        rm "$tmpfile"
      else
        echo -e "$message" | gpg --clearsign --armor --no-tty --local-user "$sign_key" --logger-fd 1 2>/dev/null | \
        zenity $zenity_size --title="Signed by $(echo -e $sign_key)" --text-info 2>/dev/null
      fi
    fi

  else

    if [[ -z "$message" ]]; then
      message=$(edit_message)
    else
      message=$(echo -e "$message" | edit_message)
    fi
    [[ $? -eq 1 ]] && exit 1
    secret=1
    choose_uids
    sign_message
  fi
}

encrypt_file () {
  if [[ ${#keys[@]} -ne 0 ]]; then
    gpg --output "${file_path}.gpg" "${keys[@]}" --always-trust --encrypt "$file_path" && \
    zenity --info --no-markup --title="$zenity_title" --text="File encrypted as $(echo -e ${file_path}.gpg) for:$(echo -e \\n${keys[@]//-r})" || \
    zenity_die "Error :( Check console output"
  else
    file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
    if [[ -f "${file_path}.gpg" ]]; then
      zenity --info --title="$zenity_title" --text="File ${file_path}.gpg exists, delete or remove it first"
      exit 1
    fi
    [[ $? -eq 1 ]] && exit 1
    choose_uids && \
    encrypt_file
  fi
}

encrypt_file_sym () {
  file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
  if [[ -f "${file_path}.gpg" ]]; then
    zenity --info --title="$zenity_title" --text="File ${file_path}.gpg exists, delete or remove it first"
    exit 1
  fi
  [[ $? -eq 1 ]] && exit 1
  gpg --output "${file_path}.gpg" $gpg_sym_cipher --symmetric "$file_path" && \
  zenity --info --no-markup --title="$zenity_title" --text="File encrypted as $(echo -e ${file_path}.gpg)" || \
  zenity_die "Error :( Check console output"
}

decrypt_file () {
  file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
  filename="$(basename $file_path)"
  dirname="$(dirname $file_path)"
  [[ -f "${file_path}.asc" ]] && file_verify=1 file_path="${file_path}.asc"
  [[ -f "${file_path}.sig" ]] && file_verify=1 file_path="${file_path}.sig"
  [[ "${filename##*.}" == 'sig' || "${filename##*.}" == 'asc' ]] && file_verify=1
  if [[ $file_verify -eq 1 ]]; then
    sig_check=$(gpg -v --logger-fd 1 --no-tty --verify "$file_path" 2>/dev/null)
    zenity --info --no-markup --title="Signature check" --text="${sig_check//gpg: }"
  else
    [[ "${filename##*.}" == 'gpg' || "${filename##*.}" == 'pgp' ]] && output="${dirname}/${filename%.*}" || output="${file_path}.output"
    if [[ -f "$output" ]]; then
      zenity --info --title="$zenity_title" --no-markup --text="File $output exists, delete or remove it first"
      exit 1
    fi
    gpg --no-tty --output "$output" --decrypt "$file_path" && \
    zenity --info --no-markup --title="$zenity_title" --text="File decrypted as $output" ||
    zenity_die "Error :( Check console output"
  fi
}

addkey () {
  local IFS='|' && \
  new_form="$(zenity --forms --title="GnuPG Wrapper" --text="Key generation" --add-entry="Nickname" --add-entry="Comment" --add-entry="Email" --add-password="Passphrase" --add-password="Repeat passphrase" 2>/dev/null)"
  [[ $? -eq 1 ]] && exit 1
  read -r -a newkey <<< "$new_form"
  [[ -z ${newkey[3]} || -z ${newkey[4]} || -z ${newkey[0]} ]] && zenity_die "Nickname and passphrase are required"
  [[ ${newkey[3]} -ne ${newkey[4]} ]] && zenity_die "Passphrases do not match"
  [[ -n ${newkey[1]} ]] && gen_comment="Name-Comment: ${newkey[1]}"
  [[ -n ${newkey[2]} ]] && gen_email="Name-Email: ${newkey[2]}"
  genkey_output=$(genkey)
  zenity --info --no-markup --title="Key generation" --text="${genkey_output//gpg: }"
}

genkey () {
  gpg --batch --gen-key --no-tty --logger-fd 1 <<EOF
%echo OpenPGP key generation:
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${newkey[0]}
$gen_comment
$gen_email
Expire-Date: 0
Passphrase: ${newkey[3]}
#%dry-run
%commit
EOF
}

delkey () {
  choose_uids
  if [[ ${#keys[@]} -ne 0 ]]; then
    delkey_output=$(gpg -v --batch --yes --no-tty --logger-fd 1 --delete-keys "${keys[@]}")
    [[ $? -eq 0 ]] && \
    zenity --info --no-markup --title="Key deletion" --text="Key(s) deleted" || \
    zenity_die "${delkey_output//gpg: }"
  fi
}

if [[ -z $1 ]]; then
  ask=$(zenity $zenity_ask_size --list  --hide-header --text="What to do?" --title "GnuPG wrapper" --radiolist  --column "Choose" --column "Action" TRUE "Encrypt" FALSE "Encrypt sym." FALSE "Decrypt / Verify" FALSE "Sign" FALSE "Sign & Encrypt" FALSE "Encrypt file" FALSE "Encrypt file sym." FALSE "Decrypt / Verify file" FALSE "Import key" FALSE "Export key" FALSE "Generate key" FALSE "Delete key")
  case $ask in
    "Encrypt")
      set e
    ;;

    "Encrypt sym.")
      set ec
    ;;

    "Decrypt / Verify")
      set d
    ;;

    "Sign")
      set s
    ;;

    "Sign & Encrypt")
      set se
    ;;

    "Encrypt file")
      set ef
    ;;

    "Encrypt file sym.")
      set efc
    ;;

    "Decrypt / Verify file")
      set df
    ;;

    "Import key")
      set import
    ;;

    "Export key")
      set export
    ;;

    "Generate key")
      set gen
    ;;

    "Delete key")
      set del
    ;;
  esac
fi

case $1 in
  e)
    zenity_title='Go ahead and type...'
    encrypt=1
    encrypt_message
  ;;

  ec)
    zenity_title='Go ahead and type...'
    encrypt_message_sym
  ;;

  d)
    zenity_title='Paste encrypted message here'
    decrypt=1
    decrypt_message
  ;;

  s)
    zenity_title='Sign message'
    sign_message
  ;;

  se|es)
    zenity_title='Sign & encrypt message'
    encrypt=1
    sign_message
  ;;

  ef|fe)
    zenity_title='Encrypt file'
    encrypt=1
    encrypt_file
  ;;

  efc|fec)
    zenity_title='Encrypt file'
    encrypt_file_sym
  ;;

  df|fd)
    zenity_title='Decrypt file'
    decrypt_file
  ;;

  im|import)
    zenity_title='Import key'
    import_key
  ;;

  ex|export)
    export=1
    shift
    [[ $1 == "--invalid" || $1 == "-i" || $1 == "i" ]] && invalid=1
    zenity_title='Export key'
    export_key
  ;;

  g|gen)
    addkey
  ;;

  del)
    delete=1
    zenity_title='Delete key(s)'
    shift
    [[ $1 == "--invalid" || $1 == "-i" || $1 == "i" ]] && invalid=1
    delkey
  ;;
esac
