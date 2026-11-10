/**
 * Class sizes (headcount) aggregation for the school teacher overview.
 *
 * Counts enrolled students for every (grade, course) combination using
 * Firestore's aggregation count() query without reading user documents.
 */

/**
 * Builds the canonical lookup key for a class: `<grade>_<course>`.
 */
export function classKey(grade, course) {
  return `${grade}_${course}`;
}

/**
 * Returns a map of class keys to enrolled student counts for every
 * grade x course combination in the school.
 *
 * @param {string} domain School email domain
 * @param {object} school School doc data containing `grades` and `courses`
 * @param {{ db: object }} deps Firestore database instance
 * @returns {Promise<Record<string, number>>} e.g. { "1_農業": 22, "1_観光": 0 }
 */
export async function classSizes(domain, school, { db }) {
  const grades = Array.isArray(school?.grades) ? school.grades : [];
  const courses = Array.isArray(school?.courses) ? school.courses : [];

  const pairs = [];
  for (const grade of grades) {
    for (const course of courses) {
      pairs.push({ grade, course });
    }
  }

  const results = await Promise.all(
    pairs.map(async ({ grade, course }) => {
      const snap = await db.collection('users')
        .where('schoolDomain', '==', domain)
        .where('grade', '==', String(grade))
        .where('course', '==', course)
        .count()
        .get();
      return [classKey(grade, course), snap.data()?.count ?? 0];
    })
  );

  return Object.fromEntries(results);
}
