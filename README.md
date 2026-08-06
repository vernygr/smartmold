# SmartMold EP

Herramienta de diagnóstico industrial para procesos de inyección de plástico, desarrollada para **ElectroPlast**.

Permite a técnicos y operadores navegar un árbol de decisión para diagnosticar defectos de inyección (rechupes, rebabas, piezas incompletas, etc.), registrar soluciones aplicadas y llevar un historial de incidencias por molde.

## Estructura del proyecto

Este repositorio contiene dos variantes de la aplicación:

- **`index.html`** — Aplicación estática de página única (HTML/CSS/JS embebidos), desplegada en Netlify. Persiste datos en `localStorage` y sincroniza opcionalmente con Google Sheets a través de un proxy CORS.
- **`app.py`** + **`templates/index.html`** — Servidor Flask con autenticación por sesión y persistencia en archivos JSON (`data/records.json`, `data/mold_records.json`). Pensado para despliegue local o en un servidor propio.

> Ambas variantes comparten la misma interfaz, pero **no comparten datos entre sí**: la versión estática usa `localStorage`/Google Sheets, mientras que la versión Flask usa su propio almacenamiento en disco.

## Funcionalidades

- Diagnóstico guiado por árbol de decisión para defectos comunes de inyección
- Registro de troubleshooting (causa raíz, solución, parámetros antes/después)
- Registro y búsqueda de incidencias por molde
- Estadísticas básicas (total de registros, moldes, últimos defectos)
- Autenticación con roles: `admin`, `operador`, `tecnico`, `supervisor`

## Ejecutar la versión Flask localmente

```bash
pip install -r requirements.txt
python app.py
```

La app quedará disponible en `http://localhost:5000`.

## Despliegue

La versión estática (`index.html`) está publicada en [smartmoldep.netlify.app](https://smartmoldep.netlify.app).
