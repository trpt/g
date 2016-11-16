#!/bin/bash

# GnuPG wrapper by Trepet
# v. 2.3
# © GPLv3

# Set if necessary
#export GNUPGHOME="$HOME/.gnupg"
#export GPGBINARY='/usr/bin/gpg2'

# Explicit choice of zenity, dmenu or rofi for key selection
#menu='dmenu'
#menu='rofi'
#menu='zenity'

# Dialog options
zenity_size="--height=600 --width=800 "
zenity_ask_size="--height=570 --width=450 "
zenity_ask_trust_size="--height=280 "
zenity_key_size_h="--height=500"
zenity_key_size_w="--width=400"
rofi_prompt="Search: "

# GPG cipher for symmetric encryption
gpg_sym_cipher='--cipher-algo AES256'

# Extension for file signing
fsig_ext='sig'

# Make detached sign when signing files?
detached_fsig='yes'

# Explicit choice of language, 'ru' and 'en' supported
#lang='en'

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
    sf - sign file
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

translate() {
  [[ -z $lang ]] && lang=${LANG:0:2}

  declare -A tr_en=([title]='GnuPG wrapper' [zenity_req]='zenity is needed to run this script' [gpg_running]='GPG is running, please wait...' [gpg_req]='GPG binary is needed to run this script!' [rofi_key]='<b>Choose key(s), Esc to finish</b>' [rofi_seckey]='<b>Choose secret key to sign</b>' [zcmd_pubkeys]='--title=Public keys' [zcmd_pubkeys_txt]='--text=Check encryption keys' [zcmd_seckeys]='--title=Secret keys' [zcmd_seckeys_txt]='--text=Choose signing key' [zcmd_exkeys]='--title=Export keys' [zcmd_exkeys_txt]='--text=Check keys to export' [zcmd_delkeys]='--title=Delete key(s)' [zcmd_delkeys_txt]='--text=Choose key(s) to delete' [zcmd_trust_txt]='--text=Check keys to change trust' [check]='Check' [key]='Key' [import]='Import' [import_result]='Import result' [export]='Export' [encrypt]='Encrypt' [decrypt]='Decrypt' [encrypted_for]='Encrypted for:' [encrypted]='Ecnrypted' [decrypted_text]='Decrypted text' [sig_check]='Signature check' [signed_by]='Signed by' [file_enc_as]='File encrypted as' [for]='for' [file_sig_created]='Signed file:' [file]='File' [file_exist_warn]='существует, сначала удалите или переместите его' [file_dec_as]='File decrypted as' [key_gen]='Key generation' [nick]='Nickname' [comment]='Comment' [email]="Email" [pass]='Passphrase' [re_pass]='Repeat passphrase' [nick_req]='Nickname required' [pass_fail]='Passphrases do not match' [key_del]='Key(s) deleted:' [key_del_txt]='Key deletion' [key_trust]='Key trust' [trust_key_ch]='Trust changed to' [ch_trust_to]='Change trust to:' [unknown]='Unknown' [no_trust]='No trust' [marginal]='Marginal' [full]='Full' [ultimate]='Ultimate' [what_todo]='What to do?' [encrypt_sym]='Encrypt with password' [dec_verify]='Decrypt or verify' [sign]='Sign' [sign_encrypt]='Sign & encrypt' [enc_file]='Ecnrypt file' [enc_file_sym]='Encrypt file with password' [sign_file]='Sign file' [dec_verify_file]='Decrypt or verify file' [import_key]='Import key' [export_key]='Export key(s)' [trust_key]='Trust control' [gen_key]='Generate key' [del_key]='Delete key(s)' [type_msg]='Go ahead and type...' [paste_msg]='Paste encrypted message here' [sign_msg]='Sign message' [sign_enc_msg]='Sign & encrypt message' [gpg_output]='GPG command result')

  declare -A tr_ru=([title]='Оболочка GnuPG' [zenity_req]='Для запуска необходима программа zenity' [gpg_running]='GPG работает, ждите...' [gpg_req]='Для запука необходима программа GPG!' [rofi_key]='<b>Выберите ключ(и), Esc для завершения</b>' [rofi_seckey]='<b>Выберите секретный ключ для подписи</b>' [zcmd_pubkeys]='--title=Открытые ключи' [zcmd_pubkeys_txt]='--text=Выберите ключи для шифрования' [zcmd_seckeys]='--title=Секретные ключи' [zcmd_seckeys_txt]='--text=Выберите ключ для подписи' [zcmd_exkeys]='--title=Экспорт ключей' [zcmd_exkeys_txt]='--text=Выберите ключи для экспорта' [zcmd_delkeys]='--title=Удалить ключ(и)' [zcmd_delkeys_txt]='--text=Выберите ключ(и) для удаления' [zcmd_trust_txt]='--text=Выберите ключ для смены доверия' [check]='Выбор' [key]='Ключ' [import]='Импорт' [import_result]='Результат импорта' [export]='Экспорт' [encrypt]='Зашифровать' [decrypt]='Расшифровать' [encrypted_for]='Зашифровано для:' [encrypted]='Зашифровано' [decrypted_text]='Расшифрованный текст' [sig_check]='Проверка подписи' [signed_by]='Подписано' [file_enc_as]='Файл зашифрован как' [for]='для' [file_sig_created]='Файл подписан:' [file]='Файл' [file_exist_warn]='существует, сначала удалите или переместите его' [file_dec_as]='Файл расшифрован как' [key_gen]='Генерация ключа' [nick]='Ник' [comment]='Комментарий' [email]="Почта" [pass]='Пароль' [re_pass]='Повтор пароля' [nick_req]='Ник обязателен' [pass_fail]='Пароли не совпадают' [key_del]='Ключи удалены:' [key_del_txt]='Удаление ключей' [key_trust]='Доверие ключа' [trust_key_ch]='Доверие изменено на' [ch_trust_to]='Изменить доверие на:' [unknown]='Неизвестное' [no_trust]='Нет доверия' [marginal]='Ограниченное' [full]='Полное' [ultimate]='Абсолютное' [what_todo]='Что нужно сделать?' [encrypt_sym]='Зашифровать паролем' [dec_verify]='Расшифровать или проверить' [sign]='Подписать' [sign_encrypt]='Подписать и зашифровать' [enc_file]='Зашифровать файл' [enc_file_sym]='Зашифровать файл паролем' [sign_file]='Подписать файл' [dec_verify_file]='Расшифровать или проверить файл' [import_key]='Импортировать ключ(и)' [export_key]='Экспортировать ключ(и)' [trust_key]='Управление доверием' [gen_key]='Генерировать ключ' [del_key]='Удалить ключ(и)' [type_msg]='Напишите сообщение...' [paste_msg]='Вставьте зашифрованное сообщение' [sign_msg]='Подписать сообщение' [sign_enc_msg]='Подписать и зашифровать сообщение' [gpg_output]='Результат выполнения команды GPG')

  case $lang in
  ru)
    [[ -z ${tr_ru[$1]} ]] && echo "${tr_en[$1]}" || echo "${tr_ru[$1]}"
  ;;
  *)
    echo "${tr_en[$1]}"
  ;;
  esac
}

if [[ $1 = @(-h|--help) ]]; then
  usage
  exit $(( $# ? 0 : 1 ))
fi

if [[ !($(command -v zenity)) ]]; then
  echo "$(translate zenity_req)"
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

zen_progress() { tee >(zenity --progress --auto-close --no-cancel --title="$(translate title)" --text "$(translate gpg_running)" --pulsate) >&1 ;}

die() {
	echo "$@" >&2
	exit 1
}

zenity_die () {
  zenity --error --no-markup --no-wrap --text "$@"
	exit 1
}

if [[ -z $GPGBINARY ]]; then
  [[ ($(command -v gpg)) ]] && export GPGBINARY='gpg'
  [[ ($(command -v gpg2)) ]] && export GPGBINARY='gpg2'
  [[ -z $GPGBINARY ]] && zenity_die "$(translate gpg_req)"
fi

rofi_cmd () {
  rofi_mesg="$(translate rofi_key)"
  [[ $secret -eq 1 ]] && rofi_mesg="$(translate rofi_seckey)"
  rofi -dmenu -i -color-window "#232832, #232832, #404552" -color-normal "#232832, #dddddd, #232832, #232832, #00CCFF" -color-active "#232832, #00b1ff, #232832, #232832, #00b1ff" -color-urgent "#232832, #ff1844, #232832, #232832, #ff1844" -opacity 90 -lines 20 -width -60 -font "mono 16" -no-levenshtein-sort -disable-history -p "$rofi_prompt" -mesg "$rofi_mesg"
}

dmenu_cmd () {
  dmenu -l 20 -b -nb \#222222 -nf \#ffffff -sb \#222222 -sf \#11dd11
}

zenity_cmd () {
  [[ $encrypt -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title="$(translate zcmd_pubkeys)" text="$(translate zcmd_pubkeys_txt)"
  [[ $secret -eq 1 ]] && zen_list_param='--radiolist' zen_sep='|' title="$(translate zcmd_seckeys)" text="$(translate zcmd_seckeys_txt)"
  [[ $export -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title="$(translate zcmd_exkeys)" text="$(translate zcmd_exkeys_txt)"
  [[ $delete -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title="$(translate zcmd_delkeys)" text="$(translate zcmd_delkeys_txt)"
  [[ $trust -eq 1 ]] && zen_list_param='--checklist' zen_sep='|' title="$(translate zcmd_pubkeys)" text="$(translate zcmd_trust_txt)"
  zenity "$zenity_key_size_h" "$zenity_key_size_w" "$text" "$title" "$zen_list_param" --list --hide-header --separator="$zen_sep" --column="$(translate check)" --column="$(translate key)"
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
  local oklabel="$(translate import)"
  local zenity_import=$(zenity $zenity_size --text-info --title="$zenity_title" --editable --ok-label="$oklabel")
  [[ -n $zenity_import ]] && \
    { local result=$(echo "$zenity_import" | "$GPGBINARY" --no-tty --import -v --logger-fd 1)
    zenity --info --no-markup --no-wrap --title="$(translate import_result)" --text="${result//gpg: }"; }
}

export_key () {
  local oklabel="$(translate export)"
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

  if [[ $secret -eq 1 ]] && [[ -z $sign_key || $sign_key = '=' ]]; then
    sign_key="=$(list_uids)"
  fi
}

edit_message () {
  [[ $decrypt -eq 1 ]] && local oklabel="$(translate decrypt)" || local oklabel="$(translate encrypt)"
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
    zenity $zenity_size --text-info --title="$(translate encrypted_for) ${keys[*]//-r =}" 2>/dev/null || \
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
  zenity $zenity_size --text-info --title="$(translate encrypted)" 2>/dev/null || \
  encrypt_message_sym
}

decrypt_message () {
  encrypted_message="$(edit_message)" || exit 1
  message=$(echo "$encrypted_message" | "$GPGBINARY" --decrypt --no-tty --logger-fd 1 2>/dev/null | sed '0,/^gpg: /s/^gpg: /\n\nGPG:\ngpg: /' | sed 's/^gpg: //')
  if [[ $old_zenity -eq 1 ]]; then
    echo -e "$message" > "$tmpfile"
    zenity $zenity_size --title="$(translate decrypted_text)" --text-info --filename="$tmpfile" 2>/dev/null
    rm "$tmpfile"
  else
    echo -e "$message" | zenity $zenity_size --title="$(translate decrypted_text)" --text-info 2>/dev/null
  fi & \
  if [[ $message == *'-----BEGIN PGP SIGNED MESSAGE-----'* ]]; then
    sig_check=$(echo -e "$message" | "$GPGBINARY" --no-tty -v --verify --logger-fd 1 2>/dev/null)
    zenity --info --no-markup --no-wrap --title="$(translate sig_check)" --text="${sig_check//gpg: }"
  fi
}

sign_message () {
  unset secret
  if [[ -n $sign_key && $sign_key != '=' ]]; then
    if [[ $encrypt -eq 1 ]]; then
      choose_uids || sign_message
      echo -e "$message" | "$GPGBINARY" -es --armor --no-tty --local-user "$sign_key" --always-trust "${keys[@]}" --logger-fd 1 2>/dev/null | \
      zenity $zenity_size --title="$(translate signed_by) ${sign_key/#=/}, $(translate encrypted_for) ${keys[*]//-r =}" --text-info 2>/dev/null
    else
      if [[ $old_zenity -eq 1 ]]; then
        echo -e "$message" | "$GPGBINARY" --clearsign --armor --no-tty --local-user "$sign_key" --logger-fd 1 2>/dev/null > "$tmpfile"
        zenity $zenity_size --title="$(translate signed_by) $(echo -e ${sign_key/#=/})" --text-info --filename="$tmpfile" 2>/dev/null
        rm "$tmpfile"
      else
        echo -e "$message" | "$GPGBINARY" --clearsign --armor --no-tty --local-user "$sign_key" --logger-fd 1 2>/dev/null | \
        zenity $zenity_size --title="$(translate signed_by) $(echo -e ${sign_key/#=/})" --text-info 2>/dev/null
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
      zenity --info --no-markup --no-wrap --title="$zenity_title" --text="$(translate file_enc_as) ${file_path}.gpg $(translate for):$(echo -e \\n${keys[@]//-r =})"
    else
      zenity_die "$encrypt_file_output"
    fi
  else
    file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
    if [[ -f "${file_path}.gpg" ]]; then
      zenity --info --no-wrap --title="$zenity_title" --text="$(translate file) ${file_path}.gpg $(translate file_exists_warn)"
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
    zenity --info --no-wrap --title="$zenity_title" --text="$(translate file) ${file_path}.gpg $(translate file_exists_warn)"
    exit 1
  fi
  [[ $? -eq 1 ]] && exit 1
  encrypt_file_sym_output=$("$GPGBINARY" --logger-fd 1 --output "${file_path}.gpg" $gpg_sym_cipher --symmetric "$file_path" 2>&1 | zen_progress)
  if [[ $? -eq 0 ]]; then
    zenity --info --no-markup --no-wrap --title="$zenity_title" --text="$(translate file_enc_as) $(echo -e ${file_path}.gpg)"
  else
    zenity_die "$encrypt_file_sym_output"
  fi
}

sign_file() {
  [[ -z $fsig_ext ]] && fsig_ext='sig'
  file_path="$(zenity --file-selection --title=$zenity_title)" || exit 1
  filename="$(basename $file_path)"
  dirname="$(dirname $file_path)"
  signed_file="${file_path}.${fsig_ext}"
  [[ -f "$signed_file" ]] && zenity_die "$(translate file) $signed_file $(translate file_exist_warn)"
  secret=1
  choose_uids
  [[ -z $sign_key || $sign_key = '=' ]] && exit 0
  if [[ "$detached_fsig" = 'yes' ]]; then
    sign_file_output=$("$GPGBINARY" --logger-fd 1 --no-tty --local-user "$sign_key" --output "$signed_file" --detach-sig "$file_path" 2>&1 | zen_progress)
  else
    sign_file_output=$("$GPGBINARY" --logger-fd 1 --no-tty --local-user "$sign_key" --output "$signed_file" --sign "$file_path" 2>&1 | zen_progress)
  fi
  if [[ $? -eq 0 ]]; then
    zenity --info --no-markup --no-wrap --title="$(translate signed_by) $(echo -e ${sign_key/#=/})" --text="$(translate file_sig_created) $(echo -e $signed_file)"
  else
    zenity_die "$sign_file_output"
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
    zenity --info --no-markup --no-wrap --title="$(translate sig_check)" --text="${sig_check//gpg: }"
  else
    [[ "${filename##*.}" == 'gpg' || "${filename##*.}" == 'pgp' ]] && output="${dirname}/${filename%.*}" || output="${file_path}.output"
    if [[ -f "$output" ]]; then
      zenity --info --title="$zenity_title" --no-markup --no-wrap --text="$(translate file) $output $(translate file_exists_warn)"
      exit 1
    fi
    decrypt_file_output=$("$GPGBINARY" --no-tty --logger-fd 1 --output "$output" --decrypt "$file_path" 2>&1 | zen_progress)
    if [[ $? -eq 0 ]]; then
      zenity --info --no-markup --no-wrap --title="$zenity_title" --text="$(translate file_dec_as) $output"
    else
      zenity_die "$decrypt_file_output"
    fi
  fi
}

addkey () {
  local IFS='|' && \
  new_form="$(zenity --forms --title="$(translate title)" --text="$(translate key_gen)" --add-entry="$(translate nick)" --add-entry="$(translate comment)" --add-entry="$(translate email)" --add-password="$(translate pass)" --add-password="$(translate re_pass)" 2>/dev/null)"
  [[ $? -eq 1 ]] && exit 1
  read -r -a newkey <<< "$new_form"
  [[ -z ${newkey[0]} ]] && zenity_die "$(translate nick_req)"
  [[ ${newkey[3]} -ne ${newkey[4]} ]] && zenity_die "$(translate pass_fail)"
  [[ -n ${newkey[3]} ]] && gen_pass="Passphrase: ${newkey[3]}"
  [[ -n ${newkey[1]} ]] && gen_comment="Name-Comment: ${newkey[1]}"
  [[ -n ${newkey[2]} ]] && gen_email="Name-Email: ${newkey[2]}"
  genkey_output=$(genkey | zen_progress)
  zenity --info --no-markup --no-wrap --title="$(translate key_gen)" --text="${genkey_output//gpg: }"
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
      printf -v msg "$(translate key_del) ${keys[*]/#=/}"
      zenity --info --no-markup --no-wrap --title="$(translate key_del_txt)" --text="$msg"
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
      zenity --info --no-markup --no-wrap --title="$(translate key_trust)" --text="$(translate trust_key_ch) $ask_trust: ${keys[*]/#=/}"
    else
      zenity_die "${trust_output//gpg: }"
    fi
  fi
}

trust_ask () {
  ask_trust=$(zenity $zenity_ask_trust_size --list --hide-header --text="$(translate ch_trust_to)" --title "$(translate title)" --radiolist  --column "$(translate choose)" --column "$(translate action)" TRUE "$(translate unknown)" FALSE "$(translate no_trust)" FALSE "$(translate marginal)" FALSE "$(translate full)" FALSE "$(translate ultimate)")
  case $ask_trust in
    "$(translate unknown)")
      trust_id=1
    ;;

    "$(translate no_trust)")
      trust_id=2
    ;;

    "$(translate marginal)")
      trust_id=3
    ;;

    "$(translate full)")
      trust_id=4
    ;;

    "$(translate ultimate)")
      trust_id=5
    ;;

    *)
      exit 0
    ;;
  esac
}

if [[ -z $1 ]]; then
  ask=$(zenity $zenity_ask_size --list  --hide-header --text="$(translate what_todo)" --title "$(translate title)" --radiolist  --column "$(translate choose)" --column "$(translate action)" TRUE "$(translate encrypt)" FALSE "$(translate encrypt_sym)" FALSE "$(translate dec_verify)" FALSE "$(translate sign)" FALSE "$(translate sign_encrypt)" FALSE "$(translate enc_file)" FALSE "$(translate enc_file_sym)" FALSE "$(translate sign_file)" FALSE "$(translate dec_verify_file)" FALSE "$(translate import_key)" FALSE "$(translate export_key)" FALSE "$(translate trust_key)"  FALSE "$(translate gen_key)" FALSE "$(translate del_key)")
  case $ask in
    "$(translate encrypt)")
      set e
    ;;

    "$(translate encrypt_sym)")
      set ec
    ;;

    "$(translate dec_verify)")
      set d
    ;;

    "$(translate sign)")
      set s
    ;;

    "$(translate sign_encrypt)")
      set se
    ;;

    "$(translate enc_file)")
      set ef
    ;;

    "$(translate enc_file_sym)")
      set efc
    ;;

    "$(translate sign_file)")
      set sf
    ;;

    "$(translate dec_verify_file)")
      set df
    ;;

    "$(translate import_key)")
      set import
    ;;

    "$(translate export_key)")
      set export
    ;;

    "$(translate trust_key)")
      set trust
    ;;

    "$(translate gen_key)")
      set gen
    ;;

    "$(translate del_key)")
      set del
    ;;
  esac
fi

case $1 in
  e)
    zenity_title="$(translate type_msg)"
    encrypt=1
    encrypt_message
  ;;

  ec)
    zenity_title="$(translate type_msg)"
    encrypt_message_sym
  ;;

  d)
    zenity_title="$(translate paste_msg)"
    decrypt=1
    decrypt_message
  ;;

  s)
    zenity_title="$(translate sign_msg)"
    sign_message
  ;;

  se|es)
    zenity_title="$(translate sign_enc_msg)"
    encrypt=1
    sign_message
  ;;

  ef|fe)
    zenity_title="$(translate enc_file)"
    encrypt=1
    encrypt_file
  ;;

  efc|fec)
    zenity_title="$(translate enc_file)"
    encrypt_file_sym
  ;;

  sf|fs)
    zenity_title="$(translate sign_file)"
    sign_file
  ;;

  df|fd)
    zenity_title="$(translate dec_file)"
    decrypt_file
  ;;

  im|import)
    zenity_title="$(translate import_key)"
    import_key
  ;;

  ex|export)
    export=1
    shift
    [[ $1 == "--invalid" || $1 == "-i" || $1 == "i" ]] && invalid=1
    zenity_title="$(translate export_key)"
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
    zenity_title="$(translate del_key)"
    shift
    [[ $1 == "--invalid" || $1 == "-i" || $1 == "i" ]] && invalid=1
    delkey
  ;;

  *)
    [[ -z "$1" ]] && exit
    output=$("$GPGBINARY" -v --logger-fd 1 $@ 2>&1 | zen_progress)
    echo "${output//gpg: }" | zenity $zenity_size --text-info --title="$(translate gpg_output)"
  ;;
esac
