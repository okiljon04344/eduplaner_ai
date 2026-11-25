const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const DRIVE = 'https://www.googleapis.com/drive/v3/files';
const SHEET_MIME = 'application/vnd.google-apps.spreadsheet';
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

async function check(res, what) {
  if (!res.ok) {
    const err = new Error(`${what} failed: HTTP ${res.status}`);
    err.status = res.status;
    throw err;
  }
  return res;
}

const tokenRequest = async (params, what) => {
  const res = await check(await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
  }), what);
  return res.json();
};

// The id_token payload is trusted without signature checks: it came straight
// from the token endpoint over TLS.
// UZ: id_token ma'lumotlari imzo tekshiruvlarisiz ishonchli hisoblanadi: u to'g'ridan-to'g'ri
// TLS orqali token endpoint'idan kelgan.
const idTokenClaims = (idToken) =>
  JSON.parse(Buffer.from(String(idToken).split('.')[1], 'base64url').toString('utf8'));

export async function exchangeCode(code, { clientId, clientSecret }) {
  const t = await tokenRequest({
    code, client_id: clientId, client_secret: clientSecret,
    redirect_uri: 'postmessage', grant_type: 'authorization_code',
  }, 'token exchange');
  const { email, hd } = idTokenClaims(t.id_token);
  return { refreshToken: t.refresh_token, accessToken: t.access_token, email, hd };
}

export async function refreshAccessToken(refreshToken, { clientId, clientSecret }) {
  const t = await tokenRequest({
    refresh_token: refreshToken, client_id: clientId, client_secret: clientSecret,
    grant_type: 'refresh_token',
  }, 'token refresh');
  return t.access_token;
}

const driveGet = async (accessToken, url, what) =>
  check(await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } }), what);

export async function getFileMeta(accessToken, fileId) {
  const url = `${DRIVE}/${encodeURIComponent(fileId)}?fields=id,name,mimeType,modifiedTime&supportsAllDrives=true`;
  return (await driveGet(accessToken, url, 'file metadata')).json();
}

export async function downloadXlsx(accessToken, meta) {
  const base = `${DRIVE}/${encodeURIComponent(meta.id)}`;
  const url = meta.mimeType === SHEET_MIME
    ? `${base}/export?mimeType=${XLSX_MIME}`
    : `${base}?alt=media&supportsAllDrives=true`;
  return Buffer.from(await (await driveGet(accessToken, url, 'file download')).arrayBuffer());
}
