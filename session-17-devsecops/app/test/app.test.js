const request = require("supertest");
const { createApp } = require("../src/app");

const app = createApp();

describe("kirana-catalog API", () => {
  test("GET /health", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  test("security headers are set by helmet", async () => {
    const res = await request(app).get("/health");
    expect(res.headers["x-content-type-options"]).toBe("nosniff");
    expect(res.headers["x-powered-by"]).toBeUndefined();
  });

  test("GET /products lists everything", async () => {
    const res = await request(app).get("/products");
    expect(res.body).toHaveLength(3);
  });

  test("GET /products?inStock=true hides out-of-stock items", async () => {
    const res = await request(app).get("/products?inStock=true");
    expect(res.body.map((p) => p.name)).not.toContain("Sugar (1 kg)");
  });

  test("GET /products/:id", async () => {
    expect((await request(app).get("/products/2")).body.name).toBe("Toor Daal (1 kg)");
    expect((await request(app).get("/products/99")).status).toBe(404);
    expect((await request(app).get("/products/abc")).status).toBe(400);
  });

  test("GET /products/:id/total validates qty", async () => {
    expect((await request(app).get("/products/1/total?qty=2")).body.total).toBe(490);
    expect((await request(app).get("/products/1/total?qty=0")).status).toBe(400);
    expect((await request(app).get("/products/1/total?qty=500")).status).toBe(400);
    expect((await request(app).get("/products/9/total")).status).toBe(404);
  });
});
