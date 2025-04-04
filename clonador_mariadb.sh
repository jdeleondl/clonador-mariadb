#!/bin/bash

# ---------------------- AYUDA, VERSIÓN Y MODOS ----------------------
if [[ "$1" == "--ayuda" || "$1" == "-h" ]]; then
  echo "Uso: ./clonador_mariadb.sh"
  echo "Este script clona una base de datos MariaDB existente en otra nueva."
  echo "Opciones disponibles:"
  echo "  --ayuda, -h     Muestra este mensaje de ayuda."
  echo "  --version       Muestra información de versión."
    echo "  --solo-respaldar  Realiza solo el respaldo de la base de datos origen."
  echo "  --solo-importar   Importa un respaldo existente a una base de datos destino."
  exit 0
elif [[ "$1" == "--version" ]]; then
  echo "Clonador de Bases de Datos MariaDB - Versión 1.0"
  echo "Autor: José De León"
  exit 0
elif [[ "$1" == "--solo-respaldar" ]]; then
  MODO="RESPALDO"
elif [[ "$1" == "--solo-importar" ]]; then
  MODO="IMPORTAR"
fi


# ------------------------------------------------------------------
# Script de clonación de bases de datos MariaDB
# Autor: José De León
# Derechos de autor © 2025 José De León
# Licencia: Uso personal y educativo permitido. Distribución con crédito.
# ------------------------------------------------------------------

# ---------------------- VALIDAR DEPENDENCIAS ----------------------

FALTANTES=()
if ! command -v bc >/dev/null; then FALTANTES+=("bc"); fi
if ! command -v pv >/dev/null; then FALTANTES+=("pv"); fi

if [ ${#FALTANTES[@]} -gt 0 ]; then
    echo "❌ Las siguientes dependencias no están instaladas:"
    for DEP in "${FALTANTES[@]}"; do echo "   - $DEP"; done
    echo
    read -p "¿Deseas que el script intente instalarlas automáticamente? [s/n]: " INSTALAR
    if [[ "$INSTALAR" == "s" || "$INSTALAR" == "S" ]]; then
        if command -v apt >/dev/null; then
            sudo apt update && sudo apt install -y "${FALTANTES[@]}"
        elif command -v dnf >/dev/null; then
            sudo dnf install -y "${FALTANTES[@]}"
        elif command -v yum >/dev/null; then
            sudo yum install -y "${FALTANTES[@]}"
        else
            echo "❌ No se detectó un gestor de paquetes compatible. Instala manualmente:"
            for DEP in "${FALTANTES[@]}"; do echo "   - $DEP"; done
            exit 1
        fi
    else
        echo "ℹ️ Puedes instalar manualmente con:"
        for DEP in "${FALTANTES[@]}"; do echo "   sudo apt install $DEP    # o    sudo dnf install $DEP"; done
        exit 1
    fi
fi

# ---------------------- CONFIGURACIÓN DE LOG ----------------------

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/clonador-$(date +%F).log"

# Verificar si se puede escribir en el archivo de log
if ! touch "$LOG_FILE" &>/dev/null; then
    echo "❌ No se puede escribir en $LOG_FILE. Verifica los permisos de la carpeta ./logs"
    exit 1
fi

log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log "🚀 Inicio del proceso de clonación."

# ---------------------- CREDENCIALES ----------------------

read -p "Ingrese el usuario de MariaDB: " USUARIO
echo "Ingrese la contraseña de MariaDB:"
read -s PASSWORD

# ---------------------- SELECCIÓN DE BASE DE DATOS ORIGEN ----------------------

while true; do
    log "📋 Obteniendo listado de bases de datos disponibles..."
    DBS=($(mysql -u "$USUARIO" -p"$PASSWORD" -N -e "SHOW DATABASES;" | grep -vE "information_schema|mysql|performance_schema|sys"))

    if [ ${#DBS[@]} -eq 0 ]; then
        log "❌ No se encontraron bases de datos disponibles para clonar."
        exit 1
    fi

    echo
    echo "📋 Bases de datos disponibles para clonar:"
    for i in "${!DBS[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${DBS[$i]}"
    done
    echo

    read -p "Seleccione el número de la base de datos de origen: " OPCION
    if [[ "$OPCION" =~ ^[0-9]+$ ]] && [ "$OPCION" -ge 1 ] && [ "$OPCION" -le ${#DBS[@]} ]; then
        DB_ORIGEN="${DBS[$((OPCION-1))]}"
        log "✅ Base de datos seleccionada: $DB_ORIGEN"
        break
    else
        log "❌ Opción inválida. Intente nuevamente ingresando un número válido."
    fi
done

# ---------------------- CÁLCULO DE ESPACIO ----------------------

log "📏 Calculando tamaño de la base de datos y espacio disponible..."

DB_SIZE_GB=$(mysql -u "$USUARIO" -p"$PASSWORD" -N -e \
    "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) FROM information_schema.tables WHERE table_schema = '$DB_ORIGEN';")

DISK_AVAILABLE_MB=$(df -Pm . | awk 'NR==2 {print $4}')
DISK_AVAILABLE_GB=$(echo "scale=2; $DISK_AVAILABLE_MB / 1024" | bc)

log "📦 Tamaño estimado: ${DB_SIZE_GB} GB"
log "💽 Espacio disponible: ${DISK_AVAILABLE_GB} GB"

MARGEN_GB=0.2
ESPACIO_REQUERIDO=$(echo "$DB_SIZE_GB + $MARGEN_GB" | bc)

if (( $(echo "$DISK_AVAILABLE_GB < $ESPACIO_REQUERIDO" | bc -l) )); then
    log "❌ Espacio insuficiente. Requiere al menos ${ESPACIO_REQUERIDO} GB."
    exit 1
fi

log "[✔] Cálculo de tamaño y espacio: 100% completado."

# ---------------------- BASE DESTINO ----------------------

while true; do
    read -p "Ingrese el nombre de la base de datos de destino: " DB_DESTINO
    DB_DESTINO=$(echo "$DB_DESTINO" | tr -cd '[:alnum:]_')
    EXISTE_DESTINO=$(mysql -u "$USUARIO" -p"$PASSWORD" -N -e "SHOW DATABASES LIKE '$DB_DESTINO';")
    if [ -n "$EXISTE_DESTINO" ]; then
        echo "❌ La base de datos '$DB_DESTINO' ya existe. Por favor elige otro nombre."
    else
        break
    fi
done

BACKUP_FILE="${DB_ORIGEN}_backup_$(date +%F_%H-%M-%S).sql"

# ---------------------- RESPALDO ----------------------

if [[ "$MODO" == "IMPORTAR" ]]; then
  echo "ℹ️ Modo importación: se omitirá el respaldo."
else
  log "📤 Iniciando respaldo de '${DB_ORIGEN}'..."
  mysqldump -u "$USUARIO" -p"$PASSWORD" --routines --triggers --events --add-drop-database --databases "$DB_ORIGEN" | \
  pv -p -e -t -b -N "Respaldo" > "$BACKUP_FILE"
  [ $? -ne 0 ] && log "❌ Error en respaldo." && exit 1
  log "[✔] Respaldo de base de datos: 100% completado."
  
  if [[ "$MODO" == "RESPALDO" ]]; then
    log "🛑 Modo respaldo activado. Finalizando después del respaldo."
    echo "📁 Respaldo guardado en: $BACKUP_FILE"
    exit 0
  fi
fi

# ---------------------- CREAR BASE DESTINO ----------------------

log "🛠️ Creando base de datos destino '${DB_DESTINO}'..."
mysql -u "$USUARIO" -p"$PASSWORD" -e "CREATE DATABASE \`$DB_DESTINO\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
[ $? -ne 0 ] && log "❌ Error al crear base destino." && exit 1
log "[✔] Creación de base de datos destino: 100% completado."

# ---------------------- IMPORTAR RESPALDO ----------------------

if [[ "$MODO" == "IMPORTAR" ]]; then
  read -p "📥 Ingrese la ruta del archivo .sql a importar: " BACKUP_FILE
  if [[ ! -f "$BACKUP_FILE" ]]; then
    log "❌ Archivo de respaldo no encontrado: $BACKUP_FILE"
    exit 1
  fi
fi

log "📥 Importando datos en '${DB_DESTINO}'..."
pv -p -e -t -b -N "Importando" "$BACKUP_FILE" | mysql -u "$USUARIO" -p"$PASSWORD" "$DB_DESTINO"
[ $? -ne 0 ] && log "❌ Error al importar datos." && exit 1
log "[✔] Importación de datos: 100% completado."

# ---------------------- ASIGNACIÓN DE USUARIO ----------------------

echo
log "🔐 ¿Qué usuario deseas que tenga acceso a la base '${DB_DESTINO}'?"
echo "1. Usar un usuario que ya tiene acceso a la base de datos origen ('$DB_ORIGEN')"
echo "2. Crear un nuevo usuario"
read -p "Selecciona una opción [1/2]: " OPCION

if [[ "$OPCION" == "1" ]]; then
    echo "🔍 Buscando usuarios con acceso a '$DB_ORIGEN'..."
    mapfile -t USUARIOS_ORIGEN < <(mysql -u "$USUARIO" -p"$PASSWORD" -N -e "SELECT CONCAT(user,'@',host) FROM mysql.db WHERE db = '$DB_ORIGEN';")

    if [ ${#USUARIOS_ORIGEN[@]} -eq 0 ]; then
        log "❌ No se encontraron usuarios con acceso a '$DB_ORIGEN'."
    else
        echo "Usuarios con acceso a '$DB_ORIGEN':"
        for i in "${!USUARIOS_ORIGEN[@]}"; do
            printf "%3d) %s\n" $((i+1)) "${USUARIOS_ORIGEN[$i]}"
        done
        echo
        read -p "Seleccione el número del usuario que desea reutilizar: " UOPCION
        USER_HOST="${USUARIOS_ORIGEN[$((UOPCION-1))]}"
        IFS='@' read -r USER_EXISTENTE HOST_EXISTENTE <<< "$USER_HOST"

        # Verificar si el usuario realmente puede conectarse
        CONEXION_OK=$(mysql -u "$USER_EXISTENTE" -p"$PASSWORD" -h "$HOST_EXISTENTE" -e "SELECT 1;" 2>/dev/null)
        if [[ -z "$CONEXION_OK" ]]; then
            log "❌ No se pudo validar el acceso del usuario '$USER_EXISTENTE'@'$HOST_EXISTENTE'. Verifica que exista y tenga permisos."
        else
            mysql -u "$USUARIO" -p"$PASSWORD" -e "GRANT ALL PRIVILEGES ON \`${DB_DESTINO}\`.* TO '$USER_EXISTENTE'@'$HOST_EXISTENTE'; FLUSH PRIVILEGES;"
            log "[✔] Permisos otorgados a '$USER_EXISTENTE'@'$HOST_EXISTENTE' en '${DB_DESTINO}'"
        fi
    fi
fi

if [[ "$OPCION" == "2" ]]; then
    read -p "Ingrese el nombre del nuevo usuario: " NEW_USER
    read -s -p "Ingrese la contraseña del nuevo usuario: " NEW_PASS
    echo
    read -p "Ingrese el host para ese usuario (ej: localhost o %): " NEW_HOST

    EXISTE_NEW=$(mysql -u "$USUARIO" -p"$PASSWORD" -e \
        "SELECT user FROM mysql.user WHERE user='$NEW_USER' AND host='$NEW_HOST';" | grep "$NEW_USER")

    if [[ -z "$EXISTE_NEW" ]]; then
        mysql -u "$USUARIO" -p"$PASSWORD" -e "CREATE USER '$NEW_USER'@'$NEW_HOST' IDENTIFIED BY '$NEW_PASS';"
        log "✅ Usuario '$NEW_USER'@'$NEW_HOST' creado."
    else
        log "ℹ️ Usuario '$NEW_USER'@'$NEW_HOST' ya existe. Se reutiliza."
    fi

    mysql -u "$USUARIO" -p"$PASSWORD" -e \
        "GRANT ALL PRIVILEGES ON \`${DB_DESTINO}\`.* TO '$NEW_USER'@'$NEW_HOST'; FLUSH PRIVILEGES;"
    log "[✔] Permisos otorgados a '$NEW_USER'@'$NEW_HOST' en '${DB_DESTINO}'"
fi

# ---------------------- CONSERVAR O ELIMINAR RESPALDO ----------------------

echo
read -p "📦 ¿Deseas conservar el archivo de respaldo '$BACKUP_FILE'? [s/n]: " CONSERVAR

if [[ "$CONSERVAR" == "n" || "$CONSERVAR" == "N" ]]; then
    rm -f "$BACKUP_FILE"
    log "🗑️ Respaldo eliminado por solicitud del usuario."
else
    log "📁 Respaldo conservado en: $BACKUP_FILE"
fi

# ---------------------- MENSAJE FINAL ----------------------

log "✅ Proceso de clonación finalizado correctamente."
echo
echo "🎯 ¡Todo listo! El proceso de clonación ha finalizado exitosamente."
echo "🗂️ Puedes revisar el log en: $LOG_FILE"
echo

