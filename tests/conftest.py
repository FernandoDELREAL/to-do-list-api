import os
import sys

# Las pruebas no deben hablar con AWS: apagamos metricas y agregamos src/ al path
os.environ["METRICS_ENABLED"] = "false"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
