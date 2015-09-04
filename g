#!/bin/bash

# GnuPG wrapper by Trepet
# © GPLv3

# Set if necessary
#export GNUPGHOME=

# Explicit choice of dmenu or rofi for key selection
#menu='dmenu'
#menu='rofi'

# Dialog options
zenity_size="--width=800 --height=600"
zenity_ask_size="--height=270 --width=250"
rofi_prompt="Search: "

# Debug
#export LANG=en-us

# Code       #
##############

if [[ -z $menu ]]; then
[[ ($(command -v dmenu)) ]] && menu='dmenu'
[[ ($(command -v rofi)) ]] && menu='rofi'
fi

if [[ -z $menu ]]; then
echo "dmenu or rofi is needed to run this script"
exit 1
fi

if [[ !($(command -v zenity)) ]]; then
echo "zenity is needed to run this script"
exit 1
fi

rofi_cmd () {
[[ $secret == 1 ]] && rofi_mesg='<b>Choose secret key to sign</b>' || rofi_mesg='<b>Choose key(s) to encrypt, Esc to finish</b>'
rofi -dmenu -bg \#222222 -fg \#ffffff -hlbg \#222222 -hlfg \#11dd11 -opacity 90 -lines 20 -width -60 -no-levenshtein-sort -disable-history -p "$rofi_prompt" -mesg "$rofi_mesg"
}

dmenu_cmd () {
dmenu -l 20 -b -nb \#222222 -nf \#ffffff -sb \#222222 -sf \#11dd11
}

list_uids () {
[[ $secret == 1 ]] && gpg_list='-K' || gpg_list='-k'
gpg $gpg_list --with-colons | grep uid: | cut -f10 -d ":" | "${menu}_cmd"
}

choose_uids () {
uid_output="$(list_uids)"
if [[ $? -ne 1 ]] && [[ $secret -ne 1 ]]; then
  keys+=("-r $uid_output")
  #echo -e ${keys[@]}
  choose_uids
fi

if [[ $secret == 1 ]]; then
  echo "$uid_output"
  unset secret
  exit 0
fi
}

edit_message () {
[[ $decrypt == 1 ]] && local oklabel='Decrypt' || local oklabel='Choose key(s)'
zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel" 2>/dev/null
}

encrypt_message () {
if [[ ${#keys[@]} -ne 0 ]]; then
  echo "$message" | gpg --armor --encrypt --always-trust "${keys[@]}" | \
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
  zenity --info --title="Signature check" --text="${sig_check//gpg:}"
fi
}

sign_message () {
unset secret
if [[ -n $sign_key ]]; then
  if [[ $encrypt == 1 ]]; then
    choose_uids
    [[ $? -eq 1 ]] && sign_message
    echo -e "$message" | gpg -es --armor --local-user $sign_key --always-trust "${keys[@]}" | \
    zenity $zenity_size --title="Signed by $(echo -e $sign_key) & encrypted for: $(echo -e ${keys[@]//-r})" --text-info 2>/dev/null
  else
    echo -e "$message" | gpg --clearsign --armor --local-user $sign_key | \
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
  sign_key=$(choose_uids) && \
  sign_message
fi
}

encrypt_file () {
if [[ ${#keys[@]} -ne 0 ]]; then
  gpg --output "${file_path}.gpg" "${keys[@]}" --always-trust --encrypt "$file_path" && \
  zenity --info --no-markup --title="$zenity_title" --text="File encrypted as $(echo -e ${file_path}.gpg) for:$(echo -e \\n${keys[@]//-r})" || \
  zenity --info --no-markup --title="$zenity_title" --text="Something went wrong :("
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
zenity --info --no-markup --title="$zenity_title" --text="Something went wrong :("
}

if [[ -z $1 ]]; then
  ask=$(zenity $zenity_ask_size --list  --hide-header --text="What to do?" --title "GnuPG wrapper" --radiolist  --column "Choose" --column "Action" TRUE "Encrypt" FALSE "Decrypt" FALSE "Sign" FALSE "Sign & Encrypt" FALSE "Encrypt file" FALSE "Decrypt file")
  case $ask in
    "Encrypt")
      set e
    ;;

    "Decrypt")
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

  esac
fi

case $1 in
    e)
      zenity_title='Go ahead and type...'
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
      encrypt_file
    ;;

    df|fd)
      zenity_title='Decrypt file'
      decrypt_file
    ;;
esac
