#!/bin/bash

# GnuPG wrapper by Trepet
# © GPLv3

# Set if necessary
#export GNUPGHOME=

# Explicit choice of dmenu or rofi for key selection
#menu='dmenu'
#menu='rofi'
#menu='zenity'

# Dialog options
zenity_size="--height=600 --width=800 "
zenity_ask_size="--height=330 --width=250 "
zenity_key_size_h="--height=500"
zenity_key_size_w="--width=350"
rofi_prompt="Search: "

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
    d - decrypt/verify message
    s - sign message
    se - sign & enrypt message
    ef - encrypt file
    df - decrypt file
    im - import key
    ex - export key

  Examples:
    $PROGRAM d
    $PROGRAM e
    $PROGRAM df

  Config (check source)
    GPG home dir:
    $GNUPGHOME

  Expired and revoked uids are ignored
EOF
}

if [[ $1 = @(-h|--help) ]]; then
  usage
  exit $(( $# ? 0 : 1 ))
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

if [[ !($(command -v zenity)) ]]; then
  echo "zenity is needed to run this script"
  exit 1
fi

rofi_cmd () {
  [[ $secret -eq 1 ]] && rofi_mesg='<b>Choose secret key to sign</b>' || rofi_mesg='<b>Choose key(s), Esc to finish</b>'
  rofi -dmenu -i -bg \#222222 -fg \#ffffff -hlbg \#222222 -hlfg \#11dd11 -opacity 90 -lines 20 -width -60 -no-levenshtein-sort -disable-history -p "$rofi_prompt" -mesg "$rofi_mesg"
}

dmenu_cmd () {
  dmenu -l 20 -b -nb \#222222 -nf \#ffffff -sb \#222222 -sf \#11dd11
}

zenity_cmd () {
  [[ $encrypt -eq 1 ]] && zen_list_param='--checklist' zen_sep='|-r ' title='--title=Public keys' text='--text=Check encryption keys'
  [[ $secret -eq 1 ]] && zen_list_param='--radiolist' zen_sep='|' title='--title=Secret keys' text='--text=Choose signing key'
  [[ ! $secret -eq 1 && ! $encrypt -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title='--title=Export keys' text='--text=Check keys to export'
  zenity "$zenity_key_size_h" "$zenity_key_size_w" "$text" "$title" "$zen_list_param" --list --hide-header --separator="$zen_sep" --column="Check" --column="Key"
}

list_uids () {
  [[ $secret -eq 1 ]] && gpg_list='-K' || gpg_list='-k'
  if [[ $menu == 'zenity' ]]; then
    gpg $gpg_list --with-colons | grep uid: | grep -v -E '^uid:e'\|'^uid:r'\|'^uid:n'\|'^uid:i' | cut -f10 -d ":" | sort -df | sed -e 's/^/FALSE\n/'| zenity_cmd
  else
    gpg $gpg_list --with-colons | grep uid: | grep -v -E '^uid:e'\|'^uid:r'\|'^uid:n'\|'^uid:i' | cut -f10 -d ":" | sort -df | ${menu}_cmd
  fi
}

import_key () {
  local oklabel='Import'
  local result=$(zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" | gpg --import --logger-fd 1)
  zenity --info --no-markup --title="Importing result" --text="${result//gpg:}"
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
  [[ $decrypt -eq 1 ]] && local oklabel='Decrypt' || local oklabel='Choose key(s)'
  zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" 2>/dev/null
}

encrypt_message () {
  if [[ ${#keys[@]} -ne 0 ]]; then
    echo "${keys[@]}"
    echo "$message" | gpg --armor --encrypt --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
    zenity $zenity_size --text-info --title="Encrypted for: $(echo -e ${keys[@]//-r})" 2>/dev/null || \
    $(unset keys && encrypt_message)
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

decrypt_message () {
  encrypted_message="$(edit_message)" || exit 1
  message=$(echo "$encrypted_message" | gpg -q --decrypt --logger-fd 1 2>/dev/null)
  echo -e "$message" | zenity $zenity_size --title="Decrypted text" --text-info 2>/dev/null &
  if [[ $message == *'-----BEGIN PGP SIGNED MESSAGE-----'* ]]; then
    sig_check=$(echo -e "$message" | gpg --verify --logger-fd 1 2>/dev/null)
    zenity --info --no-markup --title="Signature check" --text="${sig_check//gpg:}"
  fi
}

sign_message () {
  unset secret
  if [[ -n $sign_key ]]; then
    if [[ $encrypt -eq 1 ]]; then
      choose_uids
      [[ $? -eq 1 ]] && sign_message
      #echo "R: ${keys[@]}" # debug
      #echo "S: $sign_key" # debug
      echo -e "$message" | gpg -es --armor --local-user "$sign_key" --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
      zenity $zenity_size --title="Signed by $(echo -e $sign_key) & encrypted for: $(echo -e ${keys[@]//-r})" --text-info 2>/dev/null
    else
      echo -e "$message" | gpg --clearsign --armor --local-user "$sign_key" --logger-fd 1 2>/dev/null | \
      zenity $zenity_size --title="Signed by $(echo -e $sign_key)" --text-info 2>/dev/null
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
    zenity --info --no-markup --title="$zenity_title" --text="Error :( Check console output"
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

decrypt_file () {
  file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
  filename="$(basename $file_path)"
  dirname="$(dirname $file_path)"
  [[ "${filename##*.}" == 'gpg' ]] && output="${dirname}/${filename%.*}" || output="${file_path}.output"
  if [[ -f "$output" ]]; then
    zenity --info --title="$zenity_title" --no-markup --text="File $output exists, delete or remove it first"
    exit 1
  fi
  gpg --output "$output" --decrypt "$file_path" && \
  zenity --info --no-markup --title="$zenity_title" --text="File decrypted as $output" ||
  zenity --info --no-markup --title="$zenity_title" --text="Error :( Check console output"
}

if [[ -z $1 ]]; then
  ask=$(zenity $zenity_ask_size --list  --hide-header --text="What to do?" --title "GnuPG wrapper" --radiolist  --column "Choose" --column "Action" TRUE "Encrypt" FALSE "Decrypt / Verify" FALSE "Sign" FALSE "Sign & Encrypt" FALSE "Encrypt file" FALSE "Decrypt file" FALSE "Import key" FALSE "Export key")
  case $ask in
    "Encrypt")
      set e
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

    "Decrypt file")
      set df
    ;;

    "Import key")
      set import
    ;;

    "Export key")
      set export
    ;;
  esac
fi

case $1 in
  e)
    zenity_title='Go ahead and type...'
    encrypt=1
    encrypt_message
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

  df|fd)
    zenity_title='Decrypt file'
    decrypt_file
  ;;

  im|import)
    zenity_title='Import key'
    import_key
  ;;

  ex|export)
    zenity_title='Export key'
    export_key
  ;;
esac
