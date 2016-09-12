#!/bin/bash

# GnuPG wrapper by Trepet
# v. 1.6
# © GPLv3

# Set if necessary
#export GNUPGHOME="$HOME/.gnupg"
#export GPGBINARY='/usr/bin/gpg2'

# Explicit choice of dmenu or rofi for key selection
#menu='dmenu'
#menu='rofi'
#menu='zenity'

# Dialog options
zenity_size="--height=600 --width=800 "
zenity_ask_size="--height=520 "
zenity_ask_trust_size="--height=270 "
zenity_key_size_h="--height=500"
zenity_key_size_w="--width=400"
rofi_prompt="Search: "

# GPG cipher for symmetric encryption
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
    t - change key's trust
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

zen_progress() { tee >(zenity --progress --auto-close --no-cancel --title="GnuPG wrapper" --text "GPG is running, please wait ..." --pulsate) >&1 ;}

die() {
	echo "$@" >&2
	exit 1
}

zenity_die () {
  zenity --error --no-markup --text "$@"
	exit 1
}

if [[ -z $GPGBINARY ]]; then
  [[ ($(command -v gpg)) ]] && export GPGBINARY='gpg'
  [[ ($(command -v gpg2)) ]] && export GPGBINARY='gpg2'
  [[ -z $GPGBINARY ]] && zenity_die "GPG binary is needed to run this script!"
fi

rofi_cmd () {
  rofi_mesg='<b>Choose key(s), Esc to finish</b>'
  [[ $secret -eq 1 ]] && rofi_mesg='<b>Choose secret key to sign</b>'
  rofi -dmenu -i -color-window "#232832, #232832, #404552" -color-normal "#232832, #dddddd, #232832, #232832, #00CCFF" -color-active "#232832, #00b1ff, #232832, #232832, #00b1ff" -color-urgent "#232832, #ff1844, #232832, #232832, #ff1844" -opacity 90 -lines 20 -width -60 -font "mono 16" -no-levenshtein-sort -disable-history -p "$rofi_prompt" -mesg "$rofi_mesg"
}

dmenu_cmd () {
  dmenu -l 20 -b -nb \#222222 -nf \#ffffff -sb \#222222 -sf \#11dd11
}

zenity_cmd () {
  [[ $encrypt -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Public keys' text='--text=Check encryption keys'
  [[ $secret -eq 1 ]] && zen_list_param='--radiolist' zen_sep='|' title='--title=Secret keys' text='--text=Choose signing key'
  [[ $export -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Export keys' text='--text=Check keys to export'
  [[ $delete -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Delete key(s)' text='--text=Choose key(s) to delete'
  [[ $trust -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Public keys' text='--text=Check keys to change trust'
  zenity "$zenity_key_size_h" "$zenity_key_size_w" "$text" "$title" "$zen_list_param" --list --hide-header --separator="$zen_sep" --column="Check" --column="Key"
}

list_uids () {
  gpg_list='-k'
  [[ $secret -eq 1 ]] && gpg_list='-K'
  more_grep=( 'grep' '-vE' '^uid:e|^uid:r|^uid:n|^uid:i' )
  [[ $invalid -eq 1 ]] && more_grep=( 'grep' '-E' '^uid:e|^uid:r|^uid:n|^uid:i' )
  if [[ $menu == 'zenity' ]]; then
    "$GPGBINARY" $gpg_list --with-colons --fixed-list-mode | grep uid: | "${more_grep[@]}" | cut -f10 -d ":" | sort -df | sed -e 's/\\x3a/:/' | sed -e 's/^/FALSE\n/'| zenity_cmd
  else
    "$GPGBINARY" $gpg_list --with-colons --fixed-list-mode | grep uid: | "${more_grep[@]}" | cut -f10 -d ":" | sort -df | sed -e 's/\\x3a/:/' | ${menu}_cmd
  fi
}

import_key () {
  local oklabel='Import'
  local result=$(zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" | "$GPGBINARY" --no-tty --import -v --logger-fd 1)
  zenity --info --no-markup --title="Importing result" --text="${result//gpg: }"
}

export_key () {
  local oklabel='Export'
  choose_uids
  if [[ ${#keys[@]} -ne 0 ]]; then
    "$GPGBINARY" --export --armor "${keys[@]}" | zenity $zenity_size --text-info --title="$zenity_title"
  else
    exit 1
  fi
}

choose_uids () {
  if [[ $menu == 'zenity' ]]; then
    unset keys
    if [[ $secret -ne 1 ]]; then
      uid_output="$(list_uids)"
    fi && \
    local IFS='|' && \
    read -r -a keys <<< "$uid_output"
  else
    [[ $secret -ne 1 ]] && uid_output="$(list_uids)"
    if [[ $? -ne 1 ]]; then
      keys+=( "$uid_output" )
      choose_uids
      return
    fi
  fi

  if [[ $encrypt -eq 1 ]]; then
    keys=( "${keys[@]/#/'-r ='}" )
  else
    keys=( "${keys[@]/#/=}" )
  fi

  if [[ $secret -eq 1 ]] && [[ -z $sign_key ]]; then
    sign_key="=$(list_uids)"
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
    echo "$message" | "$GPGBINARY" --armor --encrypt --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
    zenity $zenity_size --text-info --title="Encrypted for: ${keys[*]//-r =}" 2>/dev/null || \
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
  echo "$message" | "$GPGBINARY" --armor --symmetric $gpg_sym_cipher --logger-fd 1 2>/dev/null | \
  zenity $zenity_size --text-info --title="Encrypted" 2>/dev/null || \
  encrypt_message_sym
}

decrypt_message () {
  encrypted_message="$(edit_message)" || exit 1
  message=$(echo "$encrypted_message" | "$GPGBINARY" --decrypt --no-tty --logger-fd 1 2>/dev/null | sed '0,/^gpg: /s/^gpg: /\n\nGPG:\ngpg: /' | sed 's/^gpg: //')
  if [[ $old_zenity -eq 1 ]]; then
    echo -e "$message" > "$tmpfile"
    zenity $zenity_size --title="Decrypted text" --text-info --filename="$tmpfile" 2>/dev/null
    rm "$tmpfile"
  else
    echo -e "$message" | zenity $zenity_size --title="Decrypted text" --text-info 2>/dev/null
  fi & \
  if [[ $message == *'-----BEGIN PGP SIGNED MESSAGE-----'* ]]; then
    sig_check=$(echo -e "$message" | "$GPGBINARY" --no-tty -v --verify --logger-fd 1 2>/dev/null)
    zenity --info --no-markup --title="Signature check" --text="${sig_check//gpg: }"
  fi
}

sign_message () {
  unset secret
  if [[ -n $sign_key ]]; then
    if [[ $encrypt -eq 1 ]]; then
      choose_uids || sign_message
      echo -e "$message" | "$GPGBINARY" -es --armor --no-tty --local-user "$sign_key" --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
      zenity $zenity_size --title="Signed by ${sign_key/#=/} & encrypted for: ${keys[*]//-r =}" --text-info 2>/dev/null
    else
      if [[ $old_zenity -eq 1 ]]; then
        echo -e "$message" | "$GPGBINARY" --clearsign --armor --no-tty --local-user "$sign_key" --logger-fd 1 2>/dev/null > "$tmpfile"
        zenity $zenity_size --title="Signed by $(echo -e ${sign_key/#=/})" --text-info --filename="$tmpfile" 2>/dev/null
        rm "$tmpfile"
      else
        echo -e "$message" | "$GPGBINARY" --clearsign --armor --no-tty --local-user "$sign_key" --logger-fd 1 2>/dev/null | \
        zenity $zenity_size --title="Signed by $(echo -e ${sign_key/#=/})" --text-info 2>/dev/null
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
    encrypt_file_output=$("$GPGBINARY" --logger-fd 1 --output "${file_path}.gpg" "${keys[@]}" --always-trust --encrypt "$file_path" 2>&1 | zen_progress)
    if [[ $? -eq 0 ]]; then
      zenity --info --no-markup --title="$zenity_title" --text="File encrypted as ${file_path}.gpg for:$(echo -e \\n${keys[@]//-r =})"
    else
      zenity_die "$encrypt_file_output"
    fi
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
  encrypt_file_sym_output=$("$GPGBINARY" --logger-fd 1 --output "${file_path}.gpg" $gpg_sym_cipher --symmetric "$file_path" 2>&1 | zen_progress)
  if [[ $? -eq 0 ]]; then
    zenity --info --no-markup --title="$zenity_title" --text="File encrypted as $(echo -e ${file_path}.gpg)"
  else
    zenity_die "$encrypt_file_sym_output"
  fi
}

decrypt_file () {
  file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
  filename="$(basename $file_path)"
  dirname="$(dirname $file_path)"
  [[ -f "${file_path}.asc" ]] && file_verify=1 file_path="${file_path}.asc"
  [[ -f "${file_path}.sig" ]] && file_verify=1 file_path="${file_path}.sig"
  [[ "${filename##*.}" == 'sig' || "${filename##*.}" == 'asc' ]] && file_verify=1
  if [[ $file_verify -eq 1 ]]; then
    sig_check=$("$GPGBINARY" -v --logger-fd 1 --no-tty --verify "$file_path" 2>/dev/null | zen_progress)
    zenity --info --no-markup --title="Signature check" --text="${sig_check//gpg: }"
  else
    [[ "${filename##*.}" == 'gpg' || "${filename##*.}" == 'pgp' ]] && output="${dirname}/${filename%.*}" || output="${file_path}.output"
    if [[ -f "$output" ]]; then
      zenity --info --title="$zenity_title" --no-markup --text="File $output exists, delete or remove it first"
      exit 1
    fi
    decrypt_file_output=$("$GPGBINARY" --no-tty --logger-fd 1 --output "$output" --decrypt "$file_path" 2>&1 | zen_progress)
    if [[ $? -eq 0 ]]; then
      zenity --info --no-markup --title="$zenity_title" --text="File decrypted as $output"
    else
      zenity_die "$decrypt_file_output"
    fi
  fi
}

addkey () {
  local IFS='|' && \
  new_form="$(zenity --forms --title="GnuPG Wrapper" --text="Key generation" --add-entry="Nickname" --add-entry="Comment" --add-entry="Email" --add-password="Passphrase" --add-password="Repeat passphrase" 2>/dev/null)"
  [[ $? -eq 1 ]] && exit 1
  read -r -a newkey <<< "$new_form"
  [[ -z ${newkey[0]} ]] && zenity_die "Nickname required"
  [[ ${newkey[3]} -ne ${newkey[4]} ]] && zenity_die "Passphrases do not match"
  [[ -n ${newkey[3]} ]] && gen_pass="Passphrase: ${newkey[3]}"
  [[ -n ${newkey[1]} ]] && gen_comment="Name-Comment: ${newkey[1]}"
  [[ -n ${newkey[2]} ]] && gen_email="Name-Email: ${newkey[2]}"
  genkey_output=$(genkey | zen_progress)
  zenity --info --no-markup --title="Key generation" --text="${genkey_output//gpg: }"
}

genkey () {
  "$GPGBINARY" --batch --gen-key --no-tty --logger-fd 1 2>&1 <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: ${newkey[0]}
$gen_comment
$gen_email
Expire-Date: 0
$gen_pass
%no-protection
%commit
EOF
}

delkey () {
  choose_uids
  if [[ ${#keys[@]} -ne 0 ]]; then
    delkey_output=$("$GPGBINARY" -v --batch --yes --no-tty --logger-fd 1 --delete-keys "${keys[@]}" 2>&1)
    if [[ $? -eq 0 ]]; then
      printf -v msg "Key(s) deleted: ${keys[*]/#=/}"
      zenity --info --no-markup --title="Key deletion" --text="$msg"
    else
      zenity_die "${delkey_output//gpg: }"
    fi
  fi
}

trust_key () {
  choose_uids
  if [[ ${#keys[@]} -ne 0 ]]; then
    trust_ask
    [[ -z $trust_id ]] && exit
    for ((i=0; i < "${#keys[@]}"; i++)); do
      trust_output=$(printf "trust\n${trust_id}\ny\n" | "$GPGBINARY" --no-tty --logger-fd 1 --command-fd 0 --edit-key "${keys[$i]}" 2>&1)
    done

    if [[ $? -eq 0 ]]; then
      zenity --info --no-markup --title="Key trust" --text="Trust changed to $ask_trust: ${keys[*]/#=/}"
    else
      zenity_die "${trust_output//gpg: }"
    fi
  fi
}

trust_ask () {
  ask_trust=$(zenity $zenity_ask_trust_size --list  --hide-header --text="Change trust to:" --title "GnuPG wrapper" --radiolist  --column "Choose" --column "Action" TRUE "Unknown" FALSE "No trust" FALSE "Marginal" FALSE "Full" FALSE "Ultimate")
  case $ask_trust in
    "Unknown")
      trust_id=1
    ;;

    "No trust")
      trust_id=2
    ;;

    "Marginal")
      trust_id=3
    ;;

    "Full")
      trust_id=4
    ;;

    "Ultimate")
      trust_id=5
    ;;
  esac
}

if [[ -z $1 ]]; then
  ask=$(zenity $zenity_ask_size --list  --hide-header --text="What to do?" --title "GnuPG wrapper" --radiolist  --column "Choose" --column "Action" TRUE "Encrypt" FALSE "Encrypt sym." FALSE "Decrypt / Verify" FALSE "Sign" FALSE "Sign & Encrypt" FALSE "Encrypt file" FALSE "Encrypt file sym." FALSE "Decrypt / Verify file" FALSE "Import key" FALSE "Export key" FALSE "Trust key"  FALSE "Generate key" FALSE "Delete key")
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

    "Trust key")
      set trust
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

  t|trust)
    trust=1
    trust_key
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

  *)
    [[ -z "$1" ]] && exit
    output=$("$GPGBINARY" -v --logger-fd 1 $@ 2>&1 | zen_progress)
    echo "${output//gpg: }" | zenity $zenity_size --text-info --title="GPG command result"
  ;;
esac
