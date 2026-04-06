from fastapi import FastAPI

app = FastAPI(title="SnapHire AI Service")


@app.get("/health")
def health():
    return {"status": "UP"}
