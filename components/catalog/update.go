package catalog

import (
	"crypto/md5"
	"encoding/hex"
	"io/ioutil"

	yaml "gopkg.in/yaml.v2"
)

// Write saves the catalog
func Write(path string, catalog Catalog) error {
	d, err := yaml.Marshal(&catalog)
	if err != nil {
		return err
	}

	comment := `# This catalog lists files stored remotely based on the files current location.
# To restore the files, run '$ cstore pull' in the same directory as this catalog file.
# If this file is deleted without running a purge command, the stores contents will be orphaned 
# with no way to recover. To get set up, visit https://github.com/turnerlabs/cstore.
`
	d = append([]byte(comment), d...)

	return ioutil.WriteFile(path, d, 0644)
}

func hashPath(path string) string {
	hasher := md5.New()
	hasher.Write([]byte(path))
	return hex.EncodeToString(hasher.Sum(nil))
}
