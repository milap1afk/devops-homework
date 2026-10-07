const express = require("express");
const helmet = require("helmet");

const products = [
  { id: 1, name: "Atta (5 kg)", price: 245, stock: 12 },
  { id: 2, name: "Toor Daal (1 kg)", price: 160, stock: 30 },
  { id: 3, name: "Sugar (1 kg)", price: 48, stock: 0 },
];

function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.use(helmet());
  app.use(express.json({ limit: "10kb" }));

  app.get("/health", (req, res) => res.json({ status: "ok", version: process.env.APP_VERSION || "dev" }));

  app.get("/products", (req, res) => {
    const inStock = req.query.inStock === "true";
    res.json(inStock ? products.filter((p) => p.stock > 0) : products);
  });

  app.get("/products/:id", (req, res) => {
    const id = Number.parseInt(req.params.id, 10);
    if (!Number.isInteger(id)) return res.status(400).json({ error: "id must be a number" });
    const product = products.find((p) => p.id === id);
    if (!product) return res.status(404).json({ error: "not found" });
    return res.json(product);
  });

  app.get("/products/:id/total", (req, res) => {
    const id = Number.parseInt(req.params.id, 10);
    const qty = Number.parseInt(req.query.qty ?? "1", 10);
    const product = products.find((p) => p.id === id);
    if (!product) return res.status(404).json({ error: "not found" });
    if (!Number.isInteger(qty) || qty < 1 || qty > 100) return res.status(400).json({ error: "qty must be 1-100" });
    return res.json({ product: product.name, qty, total: product.price * qty });
  });

  return app;
}

module.exports = { createApp, products };
