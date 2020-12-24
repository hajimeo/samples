import json
import re
import sys

def _update_dict_with_key(k, d, rtn_d):
    """
    Update the rtn_d (dit) with the given d (dict) by filtering with k (string) key|attribute
    >>> k = "attributes.checksum.sha1"
    >>> d = {"attributes" : {"checksum" : {"sha1" : "you found me" }}}
    >>> rtn_d = {"att_should_remain" : "aaaaa"}
    >>> _update_dict_with_key(k, d, rtn_d)
    {"att_should_remain": "aaaaa", "attributes.checksum.sha1": "you found me"}
    """
    if bool(rtn_d) is False:
        rtn_d = {}  # initialising
    if "\." not in k and k.find(".") > 0:
        # sys.stderr.write(str(k) + "\n") # for debug
        # returning the value only if all keys in _kNs exist
        tmp_d = d
        _kNs = k.split(".")
        for _kN in _kNs:
            if _kN in tmp_d:
                tmp_d = tmp_d[_kN]
                continue
        # Trying to create tmp_d[_k0][_k1][_k2] ...
        # value_to_store = tmp_d
        # tmp_d = {}
        # for _kN in reversed(_kNs):
        #    if bool(tmp_d) is False:
        #        tmp_d[_kN] = value_to_store
        #    else:
        #        tmp_tmp_d = tmp_d.copy()
        #        tmp_d.clear()
        #        tmp_d[_kN] = tmp_tmp_d
        # rtn_d.update(tmp_d)
        # At this moment, using the given k as key rather than above
        rtn_d[k] = tmp_d
        # sys.stderr.write(str(k) + " does not have backslash dot.\n") # for debug
    elif "\." in k:
        _tmp_k = k.replace("\\", "")
        rtn_d[_tmp_k] = d[_tmp_k]
        # sys.stderr.write(str(k) + " has backslash dot. ("+ str(_tmp_k) +"\n") # for debug
    elif k in d:
        rtn_d[k] = d[k]
        # sys.stderr.write(str(k) + "\n") # for debug
    # else:
    #    sys.stderr.write(str(k) + " not in dict\n") # for debug
    return rtn_d


def get_json(filepath="", json_str="", search_props=None, key_name=None, rtn_attrs=None, find_all=False):
    """
    Return JSON object by searching search_prop specified properties
    TODO: dirty and probably ineffcient
    :param filepath: a file path string
    :param json_str: (long) json string
    :param search_props: search hierarchy string. eg: "xxxx,yyyy,key[:=]value" (*NO* space)
    :param key_name: a key attribute in props. eg: '@class' (OrientDB), 'key' (jmx.json)
    :param rtn_attrs: attribute1,attribute2,attr3.*subattr3* (using dot) to return only those attributes' value
    :param find_all: If True, not stopping after finding one
    :return: a dict (JSON) object
    >>> get_json("", "{\"test\":\"test_result\"}", "test", "", "test")
    'test_result'
    """
    m = ptn_k = None
    if bool(search_props) and type(search_props) != list:
        search_props = search_props.split(",")
    if bool(key_name):
        ptn_k = re.compile("[\"]?" + key_name + "[\"]?\s*[:=]\s*[\"]?([^\"]+)[\"]?")
    if bool(rtn_attrs) and type(rtn_attrs) != list:
        rtn_attrs = rtn_attrs.split(",")
    _d = None
    try:
        if len(filepath) > 0:
            with open(filepath) as f:
                _d = json.load(f)
        else:
            _d = json.loads(json_str)
    except Exception as e:
        sys.stderr.write("No JSON file found from: %s ...\n" % (str(filepath)))
        pass
    if bool(_d) is False or bool(search_props) is False:
        return None
    #sys.stderr.write("DEBUG: search_props = %s \n" % (str(search_props)))
    for _p in search_props:
        if bool(_p) is False:
            continue
        if type(_d) == list:
            #sys.stderr.write("DEBUG: _p = %s and _d is list \n" % (str(_p)))
            _p_name = None
            if bool(ptn_k):
                # searching "key_name" : "some value"
                #sys.stderr.write("DEBUG: _p = %s and regex = %s \n" % (str(_p), str("[\"]?(" + key_name + ")[\"]?\s*[:=]\s*[\"]?([^\"]+)[\"]?")))
                m = ptn_k.search(_p)
                if m:
                    _p_name = m.groups()[0]
                    _p = key_name
                    #sys.stderr.write("DEBUG: _p = %s and _p_name = %s \n" % (str(_p), str(_p_name)))
            _tmp_d = []
            for _dd in _d:
                if _p not in _dd:
                    continue
                ##sys.stderr.write("DEBUG:   _p = %s is in _dd and _dd[_p] = %s \n" % (str(_p), str(_dd[_p])))
                if bool(_p_name) is False:
                    ##sys.stderr.write("DEBUG:   _p = %s is in _dd and _dd[_p] = %s and _p_name is False \n" % (str(_p), str(_dd[_p])))
                    _tmp_d.append(_dd[_p])
                elif _dd[_p] == _p_name:
                    #sys.stderr.write("DEBUG:   _p = %s and _dd[_p] is _p_name (%s) \n" % (str(_p), str(_p_name)))
                    _tmp_d.append(_dd)
                if len(_tmp_d) > 0 and bool(find_all) is False:
                    #sys.stderr.write("DEBUG: len(_tmp_d) = %s and find_all is False \n" % (str(len(_tmp_d))))
                    break
            if bool(_tmp_d) is False:
                #sys.stderr.write("DEBUG: bool(_tmp_d) is False \n")
                _d = None
                break
            if len(_tmp_d) == 1:
                _d = _tmp_d[0]
            else:
                _d = _tmp_d
        elif _p in _d:
            #sys.stderr.write("DEBUG: _p = %s is in _d \n" % (str(_p)))
            _d = _d[_p]
            continue
        else:
            #sys.stderr.write("DEBUG: _p = %s is not in _d and _d is not a list \n" % (str(_p)))
            _d = None
            break
    if bool(rtn_attrs):
        if type(_d) == list:
            _tmp_dl = []
            for _dd in _d:
                _tmp_dd = {}
                for _a in rtn_attrs:
                    _tmp_dd = _update_dict_with_key(_a, _dd, _tmp_dd)
                if len(_tmp_dd) > 0:
                    _tmp_dl.append(_tmp_dd)
            _d = _tmp_dl
        elif type(_d) == dict:
            _tmp_dd = {}
            for _a in rtn_attrs:
                _tmp_dd = _update_dict_with_key(_a, _d, _tmp_dd)
            _d = _tmp_dd
    return _d


if __name__ == '__main__':
    search_props = None
    if len(sys.argv) > 1:
        search_props = sys.argv[1]
    key_name = None
    if len(sys.argv) > 2:
        key_name = sys.argv[2]
    rtn_attrs = None
    if len(sys.argv) > 3:
        rtn_attrs = sys.argv[3]
    find_all = False
    if len(sys.argv) > 4:
        find_all = sys.argv[4]
    _no_pprint = False
    if len(sys.argv) > 5:
        _no_pprint = sys.argv[5]

    _in = sys.stdin.read()
    _d = get_json(json_str=_in, search_props=search_props, key_name=key_name, rtn_attrs=rtn_attrs, find_all=find_all)
    ##sys.stderr.write("DEBUG: len(_d) %s \n" % (len(_d)))

    if bool(_no_pprint):
        if type(_d) == list:
            print('[')
            for _i, _e in enumerate(_d):
                if len(_d) == (_i + 1):
                    print('    %s' % json.dumps(_e))
                else:
                    print('    %s,' % json.dumps(_e))
            print(']')
        elif _d is not None:
            print(json.dumps(_d))
    elif _d is not None:
        print(json.dumps(_d, indent=4, sort_keys=True))