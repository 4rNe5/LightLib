// kuromoji joins its dictionary path with Node's path.join; in the page a
// URL join is all it needs.
module.exports = {
    join: (...parts) => parts.join('/').replace(/([^:])\/{2,}/g, '$1/'),
}
