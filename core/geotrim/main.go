// geotrim drops codes from a geosite.dat or geoip.dat, so the APK carries what panels name without
// the giants (runetfreedom's geosite is over 70 MB, almost all of it two lists).
//
//	geotrim -list geosite.dat                                     codes and their sizes
//	geotrim -in geosite.dat -out small.dat -rules geosite.rules -manifest geosite.txt
//
// Rules, one per line: "-code" drops a code, "-??" drops every two-letter (country) code, "+code"
// keeps a code whatever else says. Codes not named are kept.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"os"
	"sort"
	"strings"

	"github.com/xtls/xray-core/common/geodata"
	"google.golang.org/protobuf/proto"
)

func main() {
	list := flag.String("list", "", "print the codes of this file")
	in := flag.String("in", "", "source .dat")
	out := flag.String("out", "", "trimmed .dat")
	rulesPath := flag.String("rules", "", "what to drop and keep; # comments")
	manifest := flag.String("manifest", "", "write the kept codes here")
	flag.Parse()

	if *list != "" {
		site, ip := read(*list)
		type row struct {
			code string
			size int
		}
		var rows []row
		if site != nil {
			for _, e := range site.Entry {
				rows = append(rows, row{e.Code, proto.Size(e)})
			}
		} else {
			for _, e := range ip.Entry {
				rows = append(rows, row{e.Code, proto.Size(e)})
			}
		}
		sort.Slice(rows, func(i, j int) bool { return rows[i].size > rows[j].size })
		for _, r := range rows {
			fmt.Printf("%-40s %d\n", strings.ToLower(r.code), r.size)
		}
		return
	}

	keep, drop := map[string]bool{}, map[string]bool{}
	dropCountries := false
	f, err := os.Open(*rulesPath)
	if err != nil {
		log.Fatal(err)
	}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.ToLower(strings.TrimSpace(strings.SplitN(sc.Text(), "#", 2)[0]))
		switch {
		case line == "-??":
			dropCountries = true
		case strings.HasPrefix(line, "-"):
			drop[line[1:]] = true
		case strings.HasPrefix(line, "+"):
			keep[line[1:]] = true
		}
	}
	f.Close()
	want := func(code string) bool {
		code = strings.ToLower(code)
		if keep[code] {
			return true
		}
		return !drop[code] && !(dropCountries && len(code) == 2)
	}

	site, ip := read(*in)
	var kept []string
	var data []byte
	if site != nil {
		trimmed := &geodata.GeoSiteList{}
		for _, e := range site.Entry {
			if want(e.Code) {
				trimmed.Entry = append(trimmed.Entry, e)
				kept = append(kept, strings.ToLower(e.Code))
			}
		}
		data, err = proto.Marshal(trimmed)
	} else {
		trimmed := &geodata.GeoIPList{}
		for _, e := range ip.Entry {
			if want(e.Code) {
				trimmed.Entry = append(trimmed.Entry, e)
				kept = append(kept, strings.ToLower(e.Code))
			}
		}
		data, err = proto.Marshal(trimmed)
	}
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(*out, data, 0o644); err != nil {
		log.Fatal(err)
	}
	sort.Strings(kept)
	if *manifest != "" {
		if err := os.WriteFile(*manifest, []byte(strings.Join(kept, "\n")+"\n"), 0o644); err != nil {
			log.Fatal(err)
		}
	}
	for code := range keep {
		if !contains(kept, code) {
			log.Printf("not in %s: %s", *in, code)
		}
	}
	log.Printf("%s: kept %d codes, %d bytes", *out, len(kept), len(data))
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// read decodes a geosite or a geoip list, whichever the file is.
func read(path string) (*geodata.GeoSiteList, *geodata.GeoIPList) {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	if strings.Contains(strings.ToLower(path), "geoip") {
		var ip geodata.GeoIPList
		if err := proto.Unmarshal(b, &ip); err != nil {
			log.Fatal(err)
		}
		return nil, &ip
	}
	var site geodata.GeoSiteList
	if err := proto.Unmarshal(b, &site); err != nil {
		log.Fatal(err)
	}
	return &site, nil
}
