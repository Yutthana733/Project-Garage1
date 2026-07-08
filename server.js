require('dotenv').config();
const express = require('express');
const mysql = require('mysql2');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const nodemailer = require('nodemailer'); // ✅ เพิ่มใหม่ สำหรับส่งอีเมล OTP

const app = express();
app.use(cors());
app.use(express.json());

// สร้างโฟลเดอร์ uploads
if (!fs.existsSync('./uploads')) fs.mkdirSync('./uploads');

// ตั้งค่า multer
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, './uploads/'),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `avatar_${Date.now()}${ext}`);
  },
});
const upload = multer({ storage, limits: { fileSize: 5 * 1024 * 1024 } });

// Serve รูปภาพ
app.use('/uploads', express.static('uploads'));

const db = mysql.createConnection({
  host: 'localhost',
  user: 'root',
  password: '',
  database: 'garage_app',
});

db.connect((err) => {
  if (err) {
    console.error('❌ เชื่อมต่อ DB ไม่ได้:', err.message);
  } else {
    console.log('✅ เชื่อมต่อ MySQL สำเร็จ');
  }
});

// ✅ เพิ่มใหม่: ตั้งค่าตัวส่งอีเมล (ใช้สำหรับส่ง OTP รีเซ็ตรหัสผ่าน)
// ต้องตั้งค่าใน .env หรือแก้ค่าตรงนี้ก่อนใช้งานจริง
const mailTransporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.gmail.com',
  port: Number(process.env.SMTP_PORT || 587),
  secure: false,
  auth: {
    user: process.env.SMTP_USER, // เช่น youremail@gmail.com
    pass: process.env.SMTP_PASS, // App Password 16 หลัก ไม่ใช่รหัส gmail จริง
  },
});

function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

// ===== REGISTER =====
app.post('/api/auth/register', async (req, res) => {
  const { firstName, lastName, phone, email, password, userType } = req.body;

  if (!email || !password || !userType) {
    return res.json({ success: false, message: 'กรุณากรอกข้อมูลให้ครบ' });
  }

  try {
    db.query('SELECT id FROM users WHERE email = ?', [email], async (err, results) => {
      if (err) return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });
      if (results.length > 0) {
        return res.json({ success: false, message: 'อีเมลนี้ถูกใช้งานแล้ว' });
      }

      const hashedPassword = await bcrypt.hash(password, 10);

      db.query(
        'INSERT INTO users (email, password, user_type) VALUES (?, ?, ?)',
        [email, hashedPassword, userType],
        (err, result) => {
          if (err) return res.json({ success: false, message: 'บันทึกข้อมูลไม่สำเร็จ' });

          const userId = result.insertId;

          if (userType === 'customer') {
            db.query(
              'INSERT INTO customers (user_id, first_name, last_name, phone) VALUES (?, ?, ?, ?)',
              [userId, firstName, lastName, phone],
              (err) => {
                if (err) return res.json({ success: false, message: 'บันทึกข้อมูลลูกค้าไม่สำเร็จ' });
                res.json({ success: true, message: 'สมัครสมาชิกสำเร็จ' });
              }
            );
          } else if (userType === 'repair') {
            db.query(
              'INSERT INTO garages (user_id, shop_name, owner_name, phone) VALUES (?, ?, ?, ?)',
              [userId, firstName, lastName, phone],
              (err) => {
                if (err) return res.json({ success: false, message: 'บันทึกข้อมูลอู่ซ่อมไม่สำเร็จ' });
                res.json({ success: true, message: 'สมัครสมาชิกอู่ซ่อมสำเร็จ' });
              }
            );
          }
        }
      );
    });
  } catch (e) {
    res.json({ success: false, message: 'เกิดข้อผิดพลาดภายในระบบ' });
  }
});

// ===== LOGIN =====
app.post('/api/auth/login', (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.json({ success: false, message: 'กรุณากรอกอีเมลและรหัสผ่าน' });
  }

  db.query('SELECT * FROM users WHERE email = ?', [email], async (err, results) => {
    if (err) return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });
    if (results.length === 0) {
      return res.json({ success: false, message: 'ไม่พบบัญชีนี้ในระบบ' });
    }

    const user = results[0];
    const isMatch = await bcrypt.compare(password, user.password);

    if (!isMatch) {
      return res.json({ success: false, message: 'รหัสผ่านไม่ถูกต้อง' });
    }

    const table = user.user_type === 'customer' ? 'customers' : 'garages';
    const nameCol = user.user_type === 'customer'
      ? 'first_name, last_name, phone, avatar'
      : 'shop_name, owner_name, phone, avatar';

    db.query(
      `SELECT ${nameCol} FROM ${table} WHERE user_id = ?`,
      [user.id],
      (err, profileResults) => {
        if (err) return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });

        const profile = profileResults[0] || {};

        res.json({
          success: true,
          message: 'เข้าสู่ระบบสำเร็จ',
          data: {
            user: {
              id: user.id,
              email: user.email,
              userType: user.user_type,
              ...profile,
            },
          },
        });
      }
    );
  });
});

// ===== FORGOT PASSWORD: ขอ OTP ===== ✅ เพิ่มใหม่
app.post('/api/auth/forgot-password', (req, res) => {
  const { email } = req.body;

  if (!email) {
    return res.json({ success: false, message: 'กรุณากรอกอีเมล' });
  }

  const genericMessage = 'ถ้าอีเมลนี้มีอยู่ในระบบ เราได้ส่งรหัส OTP ไปให้แล้ว';

  db.query('SELECT id FROM users WHERE email = ?', [email], async (err, results) => {
    if (err) return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });

    // ไม่บอกว่าอีเมลมีในระบบหรือไม่ (ป้องกันการสุ่มเช็ค)
    if (results.length === 0) {
      return res.json({ success: true, message: genericMessage });
    }

    try {
      const otp = generateOtp();
      const otpHash = await bcrypt.hash(otp, 10);
      const expires = new Date(Date.now() + 10 * 60 * 1000); // หมดอายุใน 10 นาที

      db.query(
        'UPDATE users SET reset_otp_hash = ?, reset_otp_expires = ? WHERE email = ?',
        [otpHash, expires, email],
        async (err2) => {
          if (err2) {
            console.error('บันทึก OTP ไม่สำเร็จ:', err2.message);
            return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });
          }

          try {
            await mailTransporter.sendMail({
              from: process.env.SMTP_FROM || process.env.SMTP_USER,
              to: email,
              subject: 'รหัส OTP สำหรับรีเซ็ตรหัสผ่าน',
              html: `
                <p>รหัส OTP ของคุณคือ:</p>
                <h2 style="letter-spacing:4px">${otp}</h2>
                <p>รหัสนี้จะหมดอายุใน 10 นาที หากคุณไม่ได้ทำรายการนี้ กรุณาเพิกเฉยต่ออีเมลนี้</p>
              `,
            });
            return res.json({ success: true, message: genericMessage });
          } catch (mailErr) {
            console.error('ส่งอีเมลไม่สำเร็จ:', mailErr.message);
            return res.json({ success: false, message: 'ส่งอีเมลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง' });
          }
        }
      );
    } catch (e) {
      return res.json({ success: false, message: 'เกิดข้อผิดพลาดภายในระบบ' });
    }
  });
});

// ===== RESET PASSWORD: ยืนยัน OTP + ตั้งรหัสผ่านใหม่ ===== ✅ เพิ่มใหม่
app.post('/api/auth/reset-password', (req, res) => {
  const { email, otp, newPassword } = req.body;

  if (!email || !otp || !newPassword) {
    return res.json({ success: false, message: 'กรุณากรอกข้อมูลให้ครบถ้วน' });
  }
  if (newPassword.length < 6) {
    return res.json({ success: false, message: 'รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร' });
  }

  db.query(
    'SELECT reset_otp_hash, reset_otp_expires FROM users WHERE email = ?',
    [email],
    async (err, results) => {
      if (err) return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });
      if (results.length === 0) {
        return res.json({ success: false, message: 'คำขอไม่ถูกต้องหรือหมดอายุ' });
      }

      const { reset_otp_hash, reset_otp_expires } = results[0];

      if (!reset_otp_hash || !reset_otp_expires || new Date(reset_otp_expires) < new Date()) {
        return res.json({ success: false, message: 'OTP หมดอายุ กรุณาขอรหัสใหม่' });
      }

      const otpMatches = await bcrypt.compare(otp, reset_otp_hash);
      if (!otpMatches) {
        return res.json({ success: false, message: 'OTP ไม่ถูกต้อง' });
      }

      const newPasswordHash = await bcrypt.hash(newPassword, 10);

      db.query(
        'UPDATE users SET password = ?, reset_otp_hash = NULL, reset_otp_expires = NULL WHERE email = ?',
        [newPasswordHash, email],
        (err2) => {
          if (err2) return res.json({ success: false, message: 'เปลี่ยนรหัสผ่านไม่สำเร็จ' });
          return res.json({ success: true, message: 'เปลี่ยนรหัสผ่านสำเร็จ กรุณาเข้าสู่ระบบใหม่' });
        }
      );
    }
  );
});

// ===== UPDATE PROFILE =====
app.put('/api/user/update', (req, res) => {
  const { userId, name, phone, address, carModel, carPlate, userType } = req.body;

  if (!userId) return res.json({ success: false, message: 'ไม่พบ userId' });

  if (userType === 'customer') {
    const parts = name.trim().split(' ');
    const firstName = parts[0] || '';
    const lastName = parts.slice(1).join(' ') || '';

    db.query(
      'UPDATE customers SET first_name = ?, last_name = ?, phone = ?, address = ?, car_model = ?, car_plate = ? WHERE user_id = ?',
      [firstName, lastName, phone, address, carModel, carPlate, userId],
      (err) => {
        if (err) return res.json({ success: false, message: 'อัปเดตไม่สำเร็จ: ' + err.message });
        res.json({ success: true, message: 'บันทึกข้อมูลสำเร็จ' });
      }
    );
  } else if (userType === 'repair') {
    db.query(
      'UPDATE garages SET shop_name = ?, phone = ?, address = ? WHERE user_id = ?',
      [name, phone, address, userId],
      (err) => {
        if (err) return res.json({ success: false, message: 'อัปเดตไม่สำเร็จ: ' + err.message });
        res.json({ success: true, message: 'บันทึกข้อมูลสำเร็จ' });
      }
    );
  }
});

// ===== GET PROFILE =====
app.get('/api/user/profile', (req, res) => {
  const { userId, userType } = req.query;
  const table = userType === 'customer' ? 'customers' : 'garages';
  const nameCol = userType === 'customer'
    ? 'first_name, last_name, phone, address, car_model, car_plate, avatar'
    : 'shop_name, owner_name, phone, address, avatar';

  db.query(
    `SELECT ${nameCol} FROM ${table} WHERE user_id = ?`,
    [userId],
    (err, results) => {
      if (err) return res.json({ success: false, message: 'เกิดข้อผิดพลาด' });
      const profile = results[0] || {};
      res.json({
        success: true,
        message: 'ดึงข้อมูลสำเร็จ',
        data: { user: { id: parseInt(userId), userType, ...profile } },
      });
    }
  );
});

// ===== UPLOAD AVATAR =====
app.post('/api/user/avatar', upload.single('avatar'), (req, res) => {
  console.log('📸 Upload avatar called');
  console.log('Body:', req.body);
  console.log('File:', req.file);

  if (!req.file) return res.json({ success: false, message: 'ไม่พบไฟล์รูปภาพ' });

  const { userId, userType } = req.body;
  const avatarUrl = `http://127.0.0.1:3000/uploads/${req.file.filename}`;
  const table = userType === 'customer' ? 'customers' : 'garages';

  db.query(
    `UPDATE ${table} SET avatar = ? WHERE user_id = ?`,
    [avatarUrl, userId],
    (err) => {
      if (err) {
        console.error('DB error:', err.message);
        return res.json({ success: false, message: 'บันทึกรูปไม่สำเร็จ' });
      }
      console.log('✅ Avatar saved:', avatarUrl);
      res.json({ success: true, message: 'อัปโหลดรูปสำเร็จ', data: { avatarUrl } });
    }
  );
});

app.listen(3000, () => {
  console.log('🚀 Server รันอยู่ที่ http://localhost:3000');
});