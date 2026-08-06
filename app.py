"""
SmartMold EP — Servidor Flask
ElectroPlast · Diagnóstico Industrial de Inyección
"""

from flask import Flask, render_template, request, jsonify, session, redirect, url_for
from functools import wraps
import json, os, uuid
from datetime import datetime, date

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "smartmold-ep-secret-2025")

# ──────────────────────────────────────────────
# CONFIGURACIÓN
# ──────────────────────────────────────────────
BASE_DIR   = os.path.dirname(os.path.abspath(__file__))
DATA_DIR   = os.path.join(BASE_DIR, "data")
RECORDS_F  = os.path.join(DATA_DIR, "records.json")
MOLDS_F    = os.path.join(DATA_DIR, "mold_records.json")

os.makedirs(DATA_DIR, exist_ok=True)

# Usuarios (usuario: contraseña)
USERS = {
    "admin":      "electroplast2025",
    "operador":   "ep1234",
    "tecnico":    "molde2025",
    "supervisor": "super2025",
}

# ──────────────────────────────────────────────
# PERSISTENCIA JSON
# ──────────────────────────────────────────────
def _load(path: str, default=None):
    if default is None:
        default = []
    if not os.path.exists(path):
        return default
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def _save(path: str, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def seed_records():
    """Inserta registros demo si la base está vacía."""
    records = _load(RECORDS_F)
    if not records:
        records = [
            {
                "id": "TS-001", "fecha": "2025-01-10",
                "categoria": "Rechupe / Hundimiento", "severidad": "alta",
                "sintoma": "Hundimiento profundo en nervio central",
                "causa_raiz": "Presión de mantenimiento insuficiente",
                "solucion": "Aumentar presión de 600 a 720 bar y tiempo a 7 seg",
                "parametro": "Presión mantenimiento",
                "valor_anterior": "600 bar", "valor_nuevo": "720 bar",
                "material": "PP", "tecnico": "Carlos M."
            },
            {
                "id": "TS-002", "fecha": "2025-01-12",
                "categoria": "Rebabas / Flash", "severidad": "media",
                "sintoma": "Flash en línea de partición lado conductor",
                "causa_raiz": "Fuerza de cierre insuficiente",
                "solucion": "Fuerza de cierre de 800 a 950 kN. Verificar paralelismo.",
                "parametro": "Fuerza de cierre",
                "valor_anterior": "800 kN", "valor_nuevo": "950 kN",
                "material": "ABS", "tecnico": "Luis R."
            },
            {
                "id": "TS-003", "fecha": "2025-01-15",
                "categoria": "Vacío / Pieza Incompleta", "severidad": "alta",
                "sintoma": "Pieza incompleta o sin llenar en extremo distal",
                "causa_raiz": "Temperatura zona 3 fuera de rango y velocidad baja",
                "solucion": "Temp Z3: 210→225°C. Velocidad: 45→70 mm/s",
                "parametro": "Temp Z3 / Velocidad",
                "valor_anterior": "210°C / 45mm/s", "valor_nuevo": "225°C / 70mm/s",
                "material": "PA66", "tecnico": "Ana G."
            },
        ]
        _save(RECORDS_F, records)

seed_records()

# ──────────────────────────────────────────────
# DECORADOR DE AUTENTICACIÓN
# ──────────────────────────────────────────────
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("logged_in"):
            return jsonify({"error": "No autenticado"}), 401
        return f(*args, **kwargs)
    return decorated

# ──────────────────────────────────────────────
# RUTAS — AUTENTICACIÓN
# ──────────────────────────────────────────────
@app.route("/api/login", methods=["POST"])
def api_login():
    data = request.get_json(force=True)
    user = (data.get("user") or "").strip().lower()
    pwd  = data.get("pass") or ""
    if USERS.get(user) == pwd:
        session["logged_in"] = True
        session["username"]  = user
        return jsonify({"ok": True, "user": user})
    return jsonify({"ok": False, "error": "Usuario o contraseña incorrectos"}), 401

@app.route("/api/logout", methods=["POST"])
def api_logout():
    session.clear()
    return jsonify({"ok": True})

@app.route("/api/me")
def api_me():
    if session.get("logged_in"):
        return jsonify({"logged_in": True, "user": session.get("username")})
    return jsonify({"logged_in": False})

# ──────────────────────────────────────────────
# RUTAS — REGISTROS TROUBLESHOOTING
# ──────────────────────────────────────────────
@app.route("/api/records", methods=["GET"])
@login_required
def get_records():
    records = _load(RECORDS_F)
    return jsonify(records)

@app.route("/api/records", methods=["POST"])
@login_required
def add_record():
    data = request.get_json(force=True)
    records = _load(RECORDS_F)

    # Generar ID auto
    next_num = len(records) + 1
    while any(r["id"] == f"TS-{next_num:03d}" for r in records):
        next_num += 1

    record = {
        "id":             f"TS-{next_num:03d}",
        "fecha":          data.get("fecha") or date.today().isoformat(),
        "categoria":      data.get("categoria", ""),
        "severidad":      data.get("severidad", ""),
        "sintoma":        data.get("sintoma", ""),
        "causa_raiz":     data.get("causa_raiz", ""),
        "solucion":       data.get("solucion", ""),
        "parametro":      data.get("parametro", ""),
        "valor_anterior": data.get("valor_anterior", ""),
        "valor_nuevo":    data.get("valor_nuevo", ""),
        "material":       data.get("material", ""),
        "tecnico":        data.get("tecnico", session.get("username", "")),
    }
    records.append(record)
    _save(RECORDS_F, records)
    return jsonify({"ok": True, "record": record}), 201

@app.route("/api/records/<record_id>", methods=["DELETE"])
@login_required
def delete_record(record_id):
    records = _load(RECORDS_F)
    new_list = [r for r in records if r["id"] != record_id]
    if len(new_list) == len(records):
        return jsonify({"error": "No encontrado"}), 404
    _save(RECORDS_F, new_list)
    return jsonify({"ok": True})

# ──────────────────────────────────────────────
# RUTAS — REGISTROS POR MOLDE
# ──────────────────────────────────────────────
@app.route("/api/molds", methods=["GET"])
@login_required
def get_molds():
    q = (request.args.get("q") or "").strip().upper()
    molds = _load(MOLDS_F)
    if q:
        molds = [m for m in molds if q in m.get("id_molde", "").upper()]
    return jsonify(molds)

@app.route("/api/molds", methods=["POST"])
@login_required
def add_mold():
    data = request.get_json(force=True)
    molds = _load(MOLDS_F)
    rec = {
        "id_molde":    (data.get("id_molde") or "").upper(),
        "fecha":       data.get("fecha") or date.today().isoformat(),
        "problema":    data.get("problema", ""),
        "diagnostico": data.get("diagnostico", ""),
        "accion":      data.get("accion", ""),
        "estado":      data.get("estado", "abierto"),
        "severidad":   data.get("severidad", "media"),
    }
    if not rec["id_molde"] or not rec["problema"]:
        return jsonify({"error": "id_molde y problema son requeridos"}), 400
    molds.append(rec)
    _save(MOLDS_F, molds)
    return jsonify({"ok": True, "record": rec}), 201

@app.route("/api/molds/<mold_id>", methods=["DELETE"])
@login_required
def delete_mold(mold_id):
    molds = _load(MOLDS_F)
    new_list = [m for m in molds if m.get("id_molde") != mold_id.upper()]
    _save(MOLDS_F, new_list)
    return jsonify({"ok": True})

# ──────────────────────────────────────────────
# RUTA — ESTADÍSTICAS
# ──────────────────────────────────────────────
@app.route("/api/stats")
@login_required
def api_stats():
    records = _load(RECORDS_F)
    molds   = _load(MOLDS_F)
    mold_ids = list({m["id_molde"] for m in molds})
    return jsonify({
        "total_records":  len(records),
        "total_molds":    len(mold_ids),
        "total_defects":  21,  # categorías del árbol de decisión
        "last_sync":      datetime.now().strftime("%H:%M"),
    })

# ──────────────────────────────────────────────
# RUTA — FRONTEND
# ──────────────────────────────────────────────
@app.route("/")
def index():
    return render_template("index.html")

# ──────────────────────────────────────────────
# ENTRADA
# ──────────────────────────────────────────────
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    debug = os.environ.get("FLASK_DEBUG", "1") == "1"
    print(f"SmartMold EP — http://localhost:{port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
