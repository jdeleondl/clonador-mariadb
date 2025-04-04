# 🛠️ Clonador de Bases de Datos MariaDB

Este script bash automatiza el proceso de clonación de una base de datos MariaDB. Permite respaldar, importar y asignar usuarios fácilmente con opciones interactivas y validaciones integradas.

## 🚀 Características

- Verificación de existencia de la base de datos origen
- Cálculo del tamaño estimado y validación del espacio en disco
- Barra de progreso en respaldo e importación
- Registro de logs detallados
- Asignación de usuario a la base clonada
- Modo de solo respaldo (`--solo-respaldar`)
- Modo de solo importación (`--solo-importar`)

## 📦 Requisitos

- `bash`
- `mysql` / `mariadb-client`
- `pv`
- `bc`

> Si alguna dependencia no está instalada, el script te preguntará si deseas instalarla automáticamente.

## 📥 Uso

```bash
chmod +x clonador_mariadb.sh
./clonador_mariadb.sh
```

### Opciones disponibles

- `--ayuda` o `-h`: Muestra la ayuda
- `--version`: Muestra información del autor y versión
- `--solo-respaldar`: Solo realiza el respaldo y guarda un `.sql`
- `--solo-importar`: Importa un `.sql` en una nueva base de datos

## ✍️ Ejemplo

```bash
./clonador_mariadb.sh --solo-respaldar
```

## 📜 Licencia

Uso personal y educativo permitido.  
Distribución autorizada siempre que se conserve el crédito.

---

**Autor:** José De León  
**© 2025**
