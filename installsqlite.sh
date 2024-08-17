#!/bin/bash

# Função para solicitar informações ao usuário e armazená-las em variáveis
function solicitar_informacoes {
    while true; do
        read -p "Digite o domínio (por exemplo, johnny.com.br): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um domínio válido no formato, por exemplo 'johnny.com.br'."
        fi
    done    

    while true; do
        read -p "Digite o e-mail para cadastro do Certbot (sem espaços): " EMAIL
        if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done
}

# Função para instalar e configurar o servidor SQLite com Node.js
function instalar_servidor_sqlite {
    # Atualizando o sistema e instalando dependências
    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y nodejs npm sqlite3 nginx certbot python3-certbot-nginx

    # Instalar o pm2 para gerenciar o processo em segundo plano
    sudo npm install -g pm2

    # Solicitar informações do usuário
    solicitar_informacoes

    # Criar arquivo de configuração Nginx para o subdomínio
    cat <<EOF > /etc/nginx/sites-available/db
server {
    server_name db.$DOMINIO;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    # Ativar o site no Nginx e configurar SSL com Certbot
    sudo ln -s /etc/nginx/sites-available/db /etc/nginx/sites-enabled/
    sudo certbot --nginx --email $EMAIL --redirect --agree-tos -d db.$DOMINIO

    # Criar o script do servidor Node.js com SQLite
    cat <<'EOF' > /root/sqlite_server.js
// Importando as dependências necessárias
const express = require('express');
const sqlite3 = require('sqlite3').verbose();
const bodyParser = require('body-parser');

// Inicializando o Express e o SQLite
const app = express();
const db = new sqlite3.Database('call_center.db');

// Configurando o middleware para parsing de JSON
app.use(bodyParser.json());

// Criando a tabela se não existir
db.serialize(() => {
  db.run(`
    CREATE TABLE IF NOT EXISTS contacts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone_number TEXT NOT NULL,
      status TEXT NOT NULL,
      notes TEXT
    )
  `);
});

// Rota para inserir um novo contato
app.post('/contacts', (req, res) => {
  const { name, phone_number, status, notes } = req.body;
  db.run(
    `INSERT INTO contacts (name, phone_number, status, notes) VALUES (?, ?, ?, ?)`,
    [name, phone_number, status, notes],
    function (err) {
      if (err) {
        return res.status(400).json({ error: err.message });
      }
      res.json({ id: this.lastID });
    }
  );
});

// Rota para obter todos os contatos
app.get('/contacts', (req, res) => {
  db.all(`SELECT * FROM contacts`, [], (err, rows) => {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    res.json({ data: rows });
  });
});

// Rota para atualizar um contato
app.put('/contacts/:id', (req, res) => {
  const { id } = req.params;
  const { status, notes } = req.body;
  db.run(
    `UPDATE contacts SET status = ?, notes = ? WHERE id = ?`,
    [status, notes, id],
    function (err) {
      if (err) {
        return res.status(400).json({ error: err.message });
      }
      res.json({ updated: this.changes });
    }
  );
});

// Rota para deletar um contato
app.delete('/contacts/:id', (req, res) => {
  const { id } = req.params;
  db.run(`DELETE FROM contacts WHERE id = ?`, id, function (err) {
    if (err) {
      return res.status(400).json({ error: err.message });
    }
    res.json({ deleted: this.changes });
  });
});

// Iniciando o servidor na porta 3000
app.listen(3000, () => {
  console.log('Servidor rodando na porta 3000');
});
EOF

    # Instalar as dependências Node.js
    npm install express sqlite3 body-parser

    # Usar pm2 para iniciar o servidor em segundo plano
    pm2 start /root/sqlite_server.js --name sqlite-server

    # Configurar pm2 para iniciar automaticamente o servidor na inicialização do sistema
    pm2 startup
    pm2 save
}

# Chamada da função principal
instalar_servidor_sqlite
